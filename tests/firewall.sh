#!/usr/bin/env bash
# Regression test for the firewall (roles/firewall): the nftables ruleset
# and the `firewall-rules` helper (the ONE rule list incl. the factory rules
# DHCP, DHCPv6, LocalSend x2, SSH), with real packets for a test port.
#
# Safe anywhere, also on a running desktop: everything runs inside a fresh
# unprivileged user + network namespace (`unshare -rn`) - its own empty
# netfilter, its own interfaces; the host's firewall/Docker never see it.
# SSH is only checked as a RULE here (listed, enabled/disabled/removed in
# the test kernel) - never reachability. Inside, three namespaces model the
# real packet paths:
#   host  - loads the ruleset; a service on :1234; a Docker-like DNAT of
#           :2345 to the "container" behind an interface named docker0
#   lan   - a colleague on the LAN (veth "lan0" <-> host "eth0")
#   ctr   - the container (veth "docker0" on the host side)
# Needs nft, iproute2, python3 + jinja2. Run by tests/run.sh; skipped there
# when unprivileged user namespaces are unavailable.

set -u
repo=$(cd "$(dirname "$0")/.." && pwd)

if [ "${1:-}" != inside ]; then
    exec unshare -rn --kill-child "$0" inside
fi

tmp=$(mktemp -d)
pids=()
trap 'kill "${pids[@]}" 2>/dev/null; rm -rf "$tmp"' EXIT
fail=0
check() { # name, condition result (0 = ok)
    if [ "$2" -ne 0 ]; then echo "FAIL $1"; fail=1; fi
}

# ---- render ruleset + helper (test paths for state, lock, nft) --------------
# nft goes through a wrapper: FAIL_APPLY=1 makes a real (non -c) apply fail,
# to prove that a failed apply leaves kernel and state as they were.
cat > "$tmp/nft" <<'EOF'
#!/bin/bash
if [ -n "${FAIL_APPLY:-}" ] && [ "$1" = -f ]; then echo "simulated failure" >&2; exit 1; fi
exec nft "$@"
EOF
chmod +x "$tmp/nft"
python3 - "$repo/roles/firewall" "$tmp" <<'EOF' || exit 1
import sys, jinja2, yaml
role, tmp = sys.argv[1:]
v = yaml.safe_load(open(role + "/defaults/main.yml"))
v.update(ssh_server_enabled=True, firewall_state_dir=tmp + "/state", firewall_ruleset=tmp + "/firewall.nft")
env = jinja2.Environment(keep_trailing_newline=True)
def render(src, dst, fix=lambda s: s):
    text = env.from_string(open(role + "/templates/" + src).read()).render(**v)
    open(dst, "w").write(fix(text))
render("firewall.nft.j2", tmp + "/firewall.nft")
render("firewall-rules.j2", tmp + "/firewall-rules",
       lambda s: s.replace('"/run/lock/workstation-firewall.lock"', repr(tmp + "/lock"))
                  .replace('NFT = "/usr/bin/nft"', "NFT = " + repr(tmp + "/nft"))
                  .replace("#!/usr/bin/python3 -I", "#!/usr/bin/env -S python3 -I"))
EOF
chmod +x "$tmp/firewall-rules"
H="$tmp/firewall-rules"
S="$tmp/state/rules.json"

# ---- the base ruleset opens no port by itself --------------------------------
nft -c -f "$tmp/firewall.nft"; check "ruleset: syntax valid" $?
! grep -E '^\s*[^#]*dport [0-9@]+.* accept' "$tmp/firewall.nft" | grep -v 'proto-dst'; check "ruleset: no port rule outside repo_rules" $?
nft add table ip filter && nft add chain ip filter DOCKER

# ---- first restore = the factory rules, in one transaction --------------------
"$H" restore; check "restore (no state yet)" $?
nft list chain ip filter DOCKER >/dev/null 2>&1; check "restore leaves other tables (Docker's) alone" $?
"$H" restore; check "restore again (reload, idempotent)" $?
chain() { nft list chain inet workstation repo_rules; }
lst() { "$H" list | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
[ "$(lst '[(x["label"], x["protocol"], x["port"], x["enabled"], x["active"]) for x in d["rules"]]')" = \
  "[('DHCP', 'UDP', 68, True, True), ('DHCPv6', 'UDP', 546, True, True), ('LocalSend – Geräteerkennung', 'UDP', 53317, True, True), ('LocalSend – Dateiübertragung', 'TCP', 53317, True, True), ('SSH', 'TCP', 22, True, True)]" ]
check "factory: the five rules, all enabled and live" $?
chain | grep -q 'udp sport 67 udp dport 68 accept';                         check "DHCP keeps its source port 67" $?
chain | grep -q 'ip6 saddr fe80::/10 udp sport 547 udp dport 546 accept';     check "DHCPv6 only from fe80::/10 (IPv6)" $?
chain | grep -q 'ip daddr 224.0.0.167 udp dport 53317 accept';               check "LocalSend discovery only to its multicast group (IPv4)" $?
chain | grep -qE '^\s*tcp dport 53317 accept';                              check "LocalSend transfer TCP 53317 (IPv4+IPv6)" $?
chain | grep -qE '^\s*tcp dport 22 accept';                                 check "SSH TCP 22 (IPv4+IPv6)" $?
[ "$(chain | grep -c accept)" = 5 ]; check "exactly five accept rules" $?
[ "$(nft list table inet workstation | grep -cE 'dport 22 ')" = 1 ]; check "no hidden second SSH rule anywhere in the table" $?
[ "$(nft -j list set inet workstation share_tcp | grep -c '"elem"')" = 0 ]; check "factory rules are not forwarded to Docker (sets empty)" $?
python3 -c "import json; d=json.load(open('$S')); assert d['version'] == 2 and len(d['rules']) == 5"; check "state written (version 2)" $?

# ---- validation ------------------------------------------------------------
refused() { # args... -> must exit 1 and change nothing (state + kernel)
    local before after kb ka
    before=$(cat "$S" 2>/dev/null); kb=$(nft list table inet workstation)
    "$H" "$@" >/dev/null 2>"$tmp/err"
    local rc=$?
    after=$(cat "$S" 2>/dev/null); ka=$(nft list table inet workstation)
    [ $rc -eq 1 ] && [ "$before" = "$after" ] && [ "$kb" = "$ka" ] && ! grep -q Traceback "$tmp/err"
}
refused add "X" 0 tcp;          check "port 0 refused" $?
refused add "X" 65536 tcp;      check "port 65536 refused" $?
refused add "X" 12ab tcp;       check "non-numeric port refused" $?
refused add "X" " 80" tcp;      check "port with space refused" $?
refused add "X" 080 tcp;        check "port with leading zero refused" $?
refused add "X" -1 tcp;         check "negative port refused" $?
refused add "X" 1234 sctp;      check "protocol sctp refused" $?
refused add "X" 1234 "tcp;";    check "protocol with junk refused" $?
refused add "" 1234 tcp;        check "empty label refused" $?
refused add "   " 1234 tcp;     check "blank label refused" $?
refused add "$(printf 'a\tb')" 1234 tcp; check "control character in label refused" $?
refused add "$(printf '%049d' 0)" 1234 tcp; check "label > 48 chars refused" $?
refused add "SSH2" 22 tcp;      check "a second rule for an existing port refused" $?
refused frobnicate;             check "unknown command refused" $?
refused enable 1234 tcp;        check "enable of a missing rule refused" $?
refused add "x" 1 tcp extra;    check "extra argument refused" $?
refused edit 546 udp "DHCPv6" 547 udp;  check "edit: port of a restricted factory rule is fixed" $?

# ---- user rules: add / enable / disable / edit / remove ---------------------
in_set() { nft -j list set inet workstation "$1" | grep -q "\"elem\": \[[^]]*\b$2\b"; }
live() { chain | grep -q "comment \"repo $1 $2\""; }
"$H" add 'Test DB; $(rm -rf /)' 1234 Tcp; check "add TCP (Tcp)" $?
! live TCP 1234 && ! in_set share_tcp 1234; check "a new rule is added disabled (not live)" $?
"$H" enable 1234 tcp && live TCP 1234 && in_set share_tcp 1234; check "enabled user rule: input + forward set" $?
"$H" add "Game" 4000 uDp && "$H" enable 4000 udp && live UDP 4000; check "add + enable UDP (uDp)" $?
"$H" add "Edit me" 7000 tcp && "$H" enable 7000 tcp; check "add + enable a rule to edit" $?
"$H" edit 7000 tcp "Edited" 7001 udp; check "edit label/port/protocol" $?
! live TCP 7000 && live UDP 7001 && [ "$(lst '[x["label"] for x in d["rules"] if x["port"] == 7001]')" = "['Edited']" ]; check "edit: old rule gone, new one live, label changed" $?
"$H" remove 7001 udp && ! live UDP 7001 && [ "$(lst '[x for x in d["rules"] if x["port"] in (7000, 7001)]')" = "[]" ]; check "remove a user rule" $?
python3 - "$S" <<'EOF'; check "state: label kept verbatim, protocol normalized" $?
import json, sys
r = {(x["port"], x["protocol"]): x for x in json.load(open(sys.argv[1]))["rules"]}
assert r[(1234, "TCP")]["label"] == "Test DB; $(rm -rf /)" and r[(4000, "UDP")]["enabled"] is True
EOF

# ---- factory rules are ordinary rules (SSH checked as a rule only) ---------
"$H" edit 546 udp "DHCPv6 (Router)" 546 udp && chain | grep -q 'ip6 saddr fe80::/10 udp sport 547 udp dport 546'; check "factory rule: label editable, restriction kept" $?
"$H" disable 22 tcp; check "disable SSH rule" $?
! live TCP 22 && [ "$(lst '[(x["enabled"], x["active"]) for x in d["rules"] if x["port"] == 22]')" = "[(False, False)]" ]; check "disabled SSH rule: still listed, not in the kernel" $?
"$H" restore && ! live TCP 22; check "disabled stays disabled after restore (boot / bootstrap)" $?
"$H" enable 22 tcp && live TCP 22; check "re-enable SSH rule" $?
"$H" remove 53317 udp && ! live UDP 53317; check "remove a factory rule (LocalSend discovery)" $?
"$H" restore && ! live UDP 53317 && [ "$(lst '[x for x in d["rules"] if x["port"] == 53317 and x["protocol"] == "UDP"]')" = "[]" ]; check "a removed factory rule stays removed after restore" $?

# ---- a failed apply changes nothing ----------------------------------------
kb=$(nft list table inet workstation); sb=$(cat "$S")
FAIL_APPLY=1 "$H" disable 1234 tcp 2>/dev/null; rc=$?
[ $rc -eq 2 ] && [ "$kb" = "$(nft list table inet workstation)" ] && [ "$sb" = "$(cat "$S")" ] && ! ls "$tmp"/state/.rules.* >/dev/null 2>&1
check "failed apply: kernel + state unchanged, no temp file left" $?

# ---- reset to the factory rules ----------------------------------------------
"$H" reset; check "reset" $?
[ "$(lst '[(x["label"], x["port"], x["protocol"], x["enabled"], x["active"]) for x in d["rules"]]')" = \
  "[('DHCP', 68, 'UDP', True, True), ('DHCPv6', 546, 'UDP', True, True), ('LocalSend – Geräteerkennung', 53317, 'UDP', True, True), ('LocalSend – Dateiübertragung', 53317, 'TCP', True, True), ('SSH', 22, 'TCP', True, True)]" ]
check "reset: five factory rules back (removed one restored, labels reset), all live" $?
! live TCP 1234 && ! in_set share_tcp 1234 && [ "$(chain | grep -c accept)" = 5 ]; check "reset: user rules gone from list, chain and sets" $?

# ---- a version-1 state (before the editor managed the factory rules) -------
printf '{"version": 1, "rules": [{"label": "Old", "port": 8080, "protocol": "TCP", "enabled": true}]}\n' > "$S"
"$H" restore; check "restore of a version-1 state" $?
[ "$(lst '[x["port"] for x in d["rules"]]')" = "[68, 546, 53317, 53317, 22, 8080]" ] && live TCP 8080 && live TCP 22; check "v1: factory rules + the old sharing rule" $?
"$H" reset

# setup for the packet tests: one enabled user rule on 1234
"$H" add "Test DB" 1234 tcp && "$H" enable 1234 tcp

# ---- real packets: host service + Docker-like DNAT --------------------------
ip link set lo up
ip link add eth0 type veth peer name lan0
ip link add docker0 type veth peer name ctr0
unshare -n sleep 600 & lanpid=$!; pids+=($lanpid)
unshare -n sleep 600 & ctrpid=$!; pids+=($ctrpid)
sleep 0.2
ip link set lan0 netns $lanpid
ip link set ctr0 netns $ctrpid
ip addr add 10.0.0.1/24 dev eth0; ip link set eth0 up
ip addr add 172.17.0.1/16 dev docker0; ip link set docker0 up
nsenter -t $lanpid -n sh -c 'ip link set lo up; ip addr add 10.0.0.2/24 dev lan0; ip link set lan0 up'
nsenter -t $ctrpid -n sh -c 'ip link set lo up; ip addr add 172.17.0.2/16 dev ctr0; ip link set ctr0 up; ip route add default via 172.17.0.1'
echo 1 > /proc/sys/net/ipv4/ip_forward
# what Docker's iptables-nft does for `-p 2345:80`
nft add table ip nat
nft add chain ip nat PREROUTING '{ type nat hook prerouting priority dstnat; }'
nft add rule ip nat PREROUTING iifname != docker0 tcp dport 2345 dnat to 172.17.0.2:80

serve() { # netns-pid|"" port
    local cmd='import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", int(sys.argv[1]))); s.listen()
while True:
    c, _ = s.accept(); c.sendall(b"ok"); c.close()'
    if [ -n "$1" ]; then nsenter -t "$1" -n python3 -c "$cmd" "$2" & else python3 -c "$cmd" "$2" & fi
    pids+=($!)
}
reach() { # netns-pid addr port -> 0 if "ok" came back
    nsenter -t "$1" -n python3 -c 'import socket,sys
s=socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=1)
sys.exit(0 if s.recv(2) == b"ok" else 1)' "$2" "$3" 2>/dev/null
}
serve "" 1234
serve "$ctrpid" 80
sleep 0.5

"$H" disable 1234 tcp
python3 -c 'import socket; socket.create_connection(("127.0.0.1", 1234), timeout=1)'; check "host service: localhost works with the rule disabled" $?
! reach $lanpid 10.0.0.1 1234; check "host service: LAN blocked with the rule disabled" $?
"$H" enable 1234 tcp
reach $lanpid 10.0.0.1 1234; check "host service: LAN allowed with the rule enabled" $?
"$H" disable 1234 tcp
! reach $lanpid 10.0.0.1 1234; check "host service: LAN blocked again right after disable" $?
"$H" enable 1234 tcp; "$H" remove 1234 tcp
! reach $lanpid 10.0.0.1 1234; check "host service: LAN blocked right after removing an enabled rule" $?
! in_set share_tcp 1234; check "remove leaves no live element behind" $?

! reach $lanpid 10.0.0.1 2345; check "docker: published port blocked from the LAN without a rule" $?
"$H" add "Web" 2345 tcp
! reach $lanpid 10.0.0.1 2345; check "docker: a newly added (disabled) rule opens nothing" $?
"$H" enable 2345 tcp
reach $lanpid 10.0.0.1 2345; check "docker: LAN allowed with a rule for the HOST port" $?
"$H" disable 2345 tcp
! reach $lanpid 10.0.0.1 2345; check "docker: LAN blocked again right after disable" $?
"$H" add "ctr port" 80 tcp; "$H" enable 80 tcp
! reach $lanpid 10.0.0.1 2345; check "docker: a rule for the container port does not open the host port" $?
"$H" remove 80 tcp
nsenter -t $lanpid -n ip route add 172.17.0.0/16 via 10.0.0.1
! reach $lanpid 172.17.0.2 80; check "docker: direct routed access to a container blocked" $?
python3 -c 'import socket,sys
s=socket.create_connection(("172.17.0.2", 80), timeout=1); sys.exit(0 if s.recv(2) == b"ok" else 1)'; check "docker: host -> container works" $?
serve "$lanpid" 8080
sleep 0.3
reach $ctrpid 10.0.0.2 8080; check "docker: container outbound works" $?
"$H" remove 2345 tcp
refused remove 2345 tcp; check "remove of a removed rule refused" $?



# ---- corrupt state: refused, never overwritten -------------------------------
kb=$(nft list table inet workstation)
echo '{not json' > "$S"
"$H" list >/dev/null 2>"$tmp/err"; [ $? -eq 2 ] && ! grep -q Traceback "$tmp/err"; check "corrupt state: list fails cleanly" $?
"$H" add "x" 5555 tcp 2>/dev/null; [ "$(cat "$S")" = '{not json' ]; check "corrupt state is never overwritten" $?
"$H" restore 2>/dev/null; [ $? -eq 2 ] && [ "$kb" = "$(nft list table inet workstation)" ]; check "corrupt state: restore fails, the loaded firewall stays" $?

[ $fail -eq 0 ] && echo "firewall: all checks passed"
exit $fail
