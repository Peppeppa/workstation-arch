#!/usr/bin/env bash
# Regression test for the firewall (roles/firewall): the nftables ruleset
# and the `firewall-rules` helper, with real packets.
#
# Safe anywhere, also on a running desktop: everything runs inside a fresh
# unprivileged user + network namespace (`unshare -rn`) - its own empty
# netfilter, its own interfaces; the host's firewall/Docker never see it.
# Inside, three namespaces model the real packet paths:
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

# ---- render ruleset + helper (test paths for state and lock) --------------
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
                  .replace("#!/usr/bin/python3 -I", "#!/usr/bin/env -S python3 -I"))
EOF
chmod +x "$tmp/firewall-rules"
H="$tmp/firewall-rules"

nft -f "$tmp/firewall.nft"; check "ruleset loads" $?
nft -f "$tmp/firewall.nft"; check "ruleset reloads (idempotent)" $?
nft add table ip filter && nft add chain ip filter DOCKER
nft -f "$tmp/firewall.nft"
nft list chain ip filter DOCKER >/dev/null 2>&1; check "a reload leaves other tables (Docker's) alone" $?

# ---- validation ------------------------------------------------------------
refused() { # args... -> must exit 1 and change nothing
    local before after
    before=$(cat "$tmp/state/rules.json" 2>/dev/null)
    "$H" "$@" >/dev/null 2>"$tmp/err"
    local rc=$?
    after=$(cat "$tmp/state/rules.json" 2>/dev/null)
    [ $rc -eq 1 ] && [ "$before" = "$after" ] && ! grep -q Traceback "$tmp/err"
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
refused add "LS" 53317 TCP;     check "LocalSend port refused (system rule)" $?
refused add "SSH" 22 tcp;       check "SSH port refused (system rule)" $?
refused frobnicate;             check "unknown command refused" $?
refused enable 1234 tcp;        check "enable of a missing rule refused" $?
refused add "x" 1 tcp extra;    check "extra argument refused" $?

# ---- add / normalize / enable / disable / remove ----------------------------
in_set() { nft -j list set inet workstation "$1" | grep -q "\"elem\": \[[^]]*\b$2\b"; }
"$H" add 'Test DB; $(rm -rf /)' 1234 Tcp; check "add TCP (Tcp)" $?
! in_set share_tcp 1234; check "a new rule is added disabled (not live)" $?
"$H" enable 1234 tcp && in_set share_tcp 1234; check "enabled TCP rule is live" $?
"$H" add "Game" 4000 uDp; check "add UDP (uDp)" $?
! in_set share_udp 4000; check "a new UDP rule is added disabled" $?
"$H" enable 4000 udp && in_set share_udp 4000; check "enabled UDP rule is live" $?
refused add "dup" 1234 TCP; check "duplicate rule refused" $?
"$H" add "Other" 1234 udp; check "same port, other protocol is a separate rule" $?
python3 - "$tmp/state/rules.json" <<'EOF'; check "state normalized (TCP/UDP), label kept verbatim" $?
import json, sys
r = json.load(open(sys.argv[1]))["rules"]
assert [(x["port"], x["protocol"], x["enabled"]) for x in r] == [(1234, "TCP", True), (4000, "UDP", True), (1234, "UDP", False)], r
assert r[0]["label"] == "Test DB; $(rm -rf /)"
EOF
for p in tcp TCP; do refused add "dup" 1234 $p; done; check "tcp/TCP duplicates refused" $?

"$H" disable 1234 TCP; check "disable" $?
! in_set share_tcp 1234; check "disabled rule is not live" $?
"$H" list | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["loaded"]
r = {(x["port"], x["protocol"]): x for x in d["rules"]}
assert r[(1234, "TCP")]["enabled"] is False and r[(1234, "TCP")]["active"] is False
assert r[(4000, "UDP")]["enabled"] is True and r[(4000, "UDP")]["active"] is True
'; check "list reports desired + live state" $?
"$H" enable 1234 tcp; check "enable" $?
in_set share_tcp 1234; check "enabled rule is live again" $?

# ---- restore after a ruleset reload (boot / bootstrap) ----------------------
nft -f "$tmp/firewall.nft"
! in_set share_tcp 1234; check "reload empties the sets" $?
"$H" restore; check "restore" $?
in_set share_tcp 1234 && in_set share_udp 4000; check "restore refills enabled rules" $?

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


# ---- status: the effective state, read-only ----------------------------------
st() { "$H" status > "$tmp/status.json" 2>"$tmp/err"; }
q() { python3 -c "import json,sys; d=json.load(open('$tmp/status.json')); print($1)"; }
serve_at() { # addr port: a listener on exactly that address
    python3 -c 'import socket,sys
fam = socket.AF_INET6 if ":" in sys.argv[1] else socket.AF_INET
s=socket.socket(fam); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((sys.argv[1], int(sys.argv[2]))); s.listen()
held = []
while True: held.append(s.accept()[0])     # keeps connections open (ESTABLISHED)' "$1" "$2" & pids+=($!)
}
serve_at 0.0.0.0 22              # "sshd": all addresses
serve_at 127.0.0.1 5555          # loopback only
serve "" 7777                    # listens, but no rule
sleep 0.4
before=$(nft list ruleset | sha256sum)
st; check "status: runs" $?
[ "$(nft list ruleset | sha256sum)" = "$before" ]; check "status: ruleset unchanged (read-only)" $?
[ "$(q 'd["loaded"], d["policy"]')" = "True drop" ]; check "status: loaded, input policy drop" $?
[ "$(q '[(x["service"], x["source"], x["iface"], x["family"], x["persistence"]) for x in d["inbound"] if x["ports"] == "22"]')" = "[('SSH (sshd, ssh_server_enabled)', [], [], None, 'persistent')]" ]
check "status: SSH = configured service, any source/interface, IPv4+IPv6, persistent" $?
[ "$(q '[s["scope"] for x in d["inbound"] if x["ports"] == "22" for s in x["listening"]]')" = "['alle Adressen']" ]; check "status: SSH rule shows its listener" $?
[ "$(q '[s["port"] for s in d["localOnly"] if s["port"] == 5555]')" = "[5555]" ]; check "status: loopback-only listener reported as local" $?
[ "$(q '[s["port"] for s in d["blocked"] if s["port"] == 7777]')" = "[7777]" ]; check "status: listening without a rule = blocked" $?
[ "$(q '[s["port"] for s in d["blocked"] if s["port"] in (22, 5555)]')" = "[]" ]; check "status: allowed / loopback listeners are not 'blocked'" $?
# an established connection from the LAN to :22 is shown with its interface
nsenter -t $lanpid -n python3 -c 'import socket,time; s=socket.create_connection(("10.0.0.1", 22)); time.sleep(3)' & pids+=($!)
sleep 0.5; st
[ "$(q '[c for x in d["inbound"] if x["ports"] == "22" for c in x["connections"]]')" = "[{'peer': '10.0.0.2', 'iface': 'eth0'}]" ]; check "status: live connection to SSH with peer + interface" $?

# a rule only for one subnet (IPv4) and one only for IPv6, added at runtime
nft add rule inet workstation input ip saddr 10.0.0.0/24 tcp dport 8080 accept
nft add rule inet workstation input ip6 saddr fd00::/8 tcp dport 9090 accept
st
[ "$(q '[(x["source"], x["family"], x["persistence"], x["service"]) for x in d["inbound"] if x["ports"] == "8080"]')" = "[(['10.0.0.0/24'], 'IPv4', 'nur zur Laufzeit', None)]" ]
check "status: subnet-only rule: its source, IPv4 only, runtime-only, no invented name" $?
[ "$(q '[(x["source"], x["family"]) for x in d["inbound"] if x["ports"] == "9090"]')" = "[(['fd00::/8'], 'IPv6')]" ]; check "status: IPv6-only rule" $?
nft -f "$tmp/firewall.nft"; "$H" restore      # back to the configuration

# sharing rules: saved+enabled = persistent with its label; a set element nobody saved = runtime-only
"$H" add "Spiel" 6000 udp; "$H" enable 6000 udp
nft add element inet workstation share_tcp '{ 6100 }'
st
[ "$(q '[(x["proto"], x["service"], x["persistence"], x["origin"]) for x in d["inbound"] if x["ports"] in ("6000", "6100")]')" = "[('TCP', None, 'nur zur Laufzeit', 'Freigabe (Einstellungen)'), ('UDP', 'Spiel', 'persistent', 'Freigabe (Einstellungen)')]" ]
check "status: sharing rules - saved = persistent + label, unsaved element = runtime" $?
"$H" disable 6000 udp; "$H" remove 6000 udp; nft delete element inet workstation share_tcp '{ 6100 }'
st
[ "$(q '[x["ports"] for x in d["inbound"] if x["origin"].startswith("Freigabe")]')" = "['4000']" ]; check "status: removed sharing rules are gone (only the earlier enabled UDP 4000 left)" $?

# a configured rule missing from the live table
h=$(nft -a list chain inet workstation input | sed -n 's/.*tcp dport 22 accept # handle \([0-9]*\)/\1/p')
nft delete rule inet workstation input handle "$h"
st
[ "$(q '[x["ports"] for x in d["missing"]]')" = "['22']" ]; check "status: configured but not live (SSH rule removed at runtime)" $?
[ "$(q '[s["port"] for s in d["blocked"] if s["port"] == 22]')" = "[22]" ]; check "status: sshd listening + rule gone = blocked" $?
nft -f "$tmp/firewall.nft"; "$H" restore

# firewall not loaded: said, and listeners are not called blocked by it
nft delete table inet workstation
st; check "status: works without the table" $?
[ "$(q 'd["loaded"], d["inbound"]')" = "False []" ]; check "status: firewall not loaded" $?
[ "$(q 'sorted(x["table"] for x in d["foreign"])')" = "['ip filter', 'ip nat']" ]; check "status: other tables named, not evaluated" $?
nft -f "$tmp/firewall.nft"; "$H" restore

# ---- corrupt state: refused, never overwritten -------------------------------
echo '{not json' > "$tmp/state/rules.json"
"$H" list >/dev/null 2>"$tmp/err"; [ $? -eq 2 ] && ! grep -q Traceback "$tmp/err"; check "corrupt state: list fails cleanly" $?
"$H" add "x" 5555 tcp 2>/dev/null; [ "$(cat "$tmp/state/rules.json")" = '{not json' ]; check "corrupt state is never overwritten" $?
! in_set share_tcp 5555; check "corrupt state: nothing opened" $?

[ $fail -eq 0 ] && echo "firewall: all checks passed"
exit $fail
