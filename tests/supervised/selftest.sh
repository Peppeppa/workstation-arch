#!/usr/bin/env bash
# Simulations for testctl.py (fake ssh, local temp dirs, ~30 s). Exit 0 = all pass.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SIM=$(mktemp -d); export SIM
trap 'rm -rf "$SIM"' EXIT
export TESTCTL_SSH="python3 $here/stub-ssh.py" TESTCTL_TIME_SCALE=0.01 TESTCTL_SUDO="$here/stub-sudo.sh"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails+1)); fi; }
cat > "$SIM/plan.json" <<'P'
{"ssh_policy": {"grace": 120, "window": 600, "interval": 10},
 "tests": {
  "ok":     {"steps": [{"cmd": "echo hello", "expect_re": "hello", "capture": "greet"},
                       {"cmd": "echo {greet}-again", "expect_re": "hello-again"}]},
  "slow":   {"steps": [{"cmd": "echo run >> slowruns; sleep 3; echo done", "expect_re": "done", "timeout": 30, "poll": 1}]},
  "destr":  {"steps": [{"cmd": "echo x >> counter; echo did", "expect_re": "did", "destructive": true}]},
  "bad":    {"steps": [{"cmd": "echo unexpected", "expect_re": "^expected$"}]},
  "dep":    {"requires": ["bad"], "steps": [{"cmd": "echo never >> depran"}]},
  "sreboot": {"steps": [{"cmd": "cat /proc/sys/kernel/random/boot_id", "capture": "boot_id"},
                       {"cmd": "echo issued >> reboots; echo bootC > boot_id", "sudo": true, "destructive": true, "expect_disconnect": true},
                       {"kind": "wait_ssh", "timeout": 600, "interval": 10, "require_new_boot": true}]},
  "typed":  {"steps": [{"cmd": "IFS= read -r x; [ ${#x} = 10 ] && echo typed-ok", "sudo": true, "secret_to_cmd": true, "expect_re": "typed-ok"}]},
  "gate":   {"steps": [{"kind": "approve", "text": "reboot?"}, {"cmd": "echo gated"}]},
  "reboot": {"steps": [{"cmd": "cat /proc/sys/kernel/random/boot_id", "capture": "boot_id"},
                       {"cmd": "echo issued >> reboots; echo bootB > boot_id", "destructive": true, "expect_disconnect": true},
                       {"kind": "wait_ssh", "timeout": 600, "interval": 10, "require_new_boot": true},
                       {"cmd": "cat boot_id", "expect_re": "bootB"}]}
 }}
P
ctl() { local st=$1; shift; python3 "$here/testctl.py" --state "$SIM/$st" --plan "$SIM/plan.json" --host "h=hostA" --host "w=alt-hostA" "$@"; }
scen() { echo "$1" > "$SIM/scenario.json"; }
status() { python3 -c "import json;print(json.load(open('$SIM/$1/state.json'))['tests']['$2']['status'])"; }
reset_host() { rm -rf "$SIM/hostA"; mkdir -p "$SIM/hostA"; echo bootA > "$SIM/hostA/boot_id"; scen '{}'; }

# 1 SSH loss mid-run (both paths down for some calls)
reset_host; scen '{"hostA": {"down": [2,3,4]}, "alt-hostA": {"down": [1,2,3]}}'
ctl s1 run ok >/dev/null; check "ssh loss mid-run -> recovered, PASS" '[ $? = 0 ] && [ "$(status s1 ok)" = PASS ]'

# 2 SSH back after a delay longer than the grace period, primary path only
reset_host; scen "{\"hostA\": {\"down_until\": $(( $(date +%s) + 3 ))}, \"alt-hostA\": {\"dead\": true}}"
out=$(ctl s2 run ok); rc=$?
check "ssh delayed return -> PASS after reconnect" '[ $rc = 0 ] && grep -q "SSH back" <<<"$out"'

# 3 permanent loss -> WAITING_FOR_LOCAL_INTERVENTION, resume later
reset_host; scen '{"hostA": {"dead": true}, "alt-hostA": {"dead": true}}'
ctl s3 run ok >/dev/null; rc=$?
check "permanent loss -> exit 3 WAITING_FOR_LOCAL_INTERVENTION" '[ $rc = 3 ] && [ "$(status s3 ok)" = WAITING_FOR_LOCAL_INTERVENTION ]'
scen '{}'; ctl s3 run ok >/dev/null
check "resume after local intervention -> PASS" '[ $? = 0 ] && [ "$(status s3 ok)" = PASS ]'

# 4/5 controller killed mid-step, restart from checkpoint, no second launch
reset_host
ctl s4 run slow >/dev/null & pid=$!; sleep 1.5; kill -9 $pid; wait $pid 2>/dev/null
check "killed controller leaves RUNNING checkpoint" '[ "$(status s4 slow)" = RUNNING ]'
ctl s4 run slow >/dev/null
check "restart from checkpoint -> PASS, remote ran once" '[ $? = 0 ] && [ "$(wc -l < $SIM/hostA/slowruns)" = 1 ] && [ $(ls -d $SIM/hostA/.cache/testctl/*.slow.*.lock | wc -l) = 1 ]'

# 6 duplicate invocation while one runs
reset_host
ctl s6 run slow >/dev/null & pid=$!; sleep 0.7
ctl s6 run slow >/dev/null 2>&1; rc=$?; wait $pid
check "duplicate controller refused (exit 4), work done once" '[ $rc = 4 ] && [ "$(wc -l < $SIM/hostA/slowruns)" = 1 ]'
ctl s6 run slow >/dev/null
check "rerun of a PASSed test does nothing" '[ "$(wc -l < $SIM/hostA/slowruns)" = 1 ]'

# 7 unexpected result -> FAIL, kept; dependent test BLOCKED
reset_host
ctl s7 run bad >/dev/null; rc=$?; ctl s7 run bad >/dev/null; rc2=$?; ctl s7 run dep >/dev/null; rc3=$?
check "unexpected output -> FAIL (exit 1), not rerun" '[ $rc = 1 ] && [ $rc2 = 1 ] && [ "$(status s7 bad)" = FAIL ]'
check "dependent test BLOCKED, never run" '[ $rc3 = 2 ] && [ "$(status s7 dep)" = BLOCKED ] && [ ! -e $SIM/hostA/depran ]'

# 8 remote command ran but its reply was lost (launch and result fetch)
reset_host; scen '{"hostA": {"lose_reply": [1, 2]}, "alt-hostA": {"dead": true}}'
ctl s8 run destr >/dev/null
check "lost replies on a destructive step -> run once, PASS" '[ $? = 0 ] && [ "$(wc -l < $SIM/hostA/counter)" = 1 ]'

# 9 destructive launch never arrived (host down), then host back
reset_host; scen '{"hostA": {"dead": true}, "alt-hostA": {"dead": true}}'
ctl s9 run destr >/dev/null; rc=$?
check "destructive launch unreachable -> WAITING, nothing ran" '[ $rc = 3 ] && [ ! -e $SIM/hostA/counter ]'
scen '{}'; ctl s9 run destr >/dev/null
check "resume launches it exactly once" '[ $? = 0 ] && [ "$(wc -l < $SIM/hostA/counter)" = 1 ]'

# 10 reboot step: no relaunch, new boot id required (SSH alone is not success)
reset_host; scen "{\"hostA\": {\"down_until\": 0}}"
ctl s10 run reboot >/dev/null; rc=$?
ctl s10 run reboot >/dev/null
check "reboot flow -> PASS, reboot issued once" '[ $rc = 0 ] && [ "$(wc -l < $SIM/hostA/reboots)" = 1 ]'
reset_host
python3 - "$SIM" <<'PY'
import json,sys,os
# old boot id stays: wait_ssh must not accept it
p=json.load(open(sys.argv[1]+"/plan.json")); p["tests"]["reboot"]["steps"][1]["cmd"]="echo issued >> reboots"
p["tests"]["reboot"]["steps"][2]["timeout"]=300; json.dump(p,open(sys.argv[1]+"/plan2.json","w"))
PY
python3 "$here/testctl.py" --state "$SIM/s10b" --plan "$SIM/plan2.json" --host "h=hostA" run reboot >/dev/null; rc=$?
check "same boot id after 'reboot' -> not success (WAITING)" '[ $rc = 3 ]'

# 11 approval gate
reset_host
ctl s11 run gate >/dev/null; rc=$?
ctl s11 approve gate >/dev/null; ctl s11 run gate >/dev/null
check "approval gate stops, approve + rerun -> PASS" '[ $rc = 2 ] && [ $? = 0 ] && [ "$(status s11 gate)" = PASS ]'

# 12 sudo step: password via stdin only, reply lost (reboot), run once
reset_host; scen '{"hostA": {"lose_reply": [2]}, "alt-hostA": {"dead": true}}'
echo sim-secret | ctl s12 --secret-stdin run sreboot >/dev/null; rc=$?
echo sim-secret | ctl s12 --secret-stdin run sreboot >/dev/null
check "sudo reboot step: password via stdin, issued once, PASS" '[ $rc = 0 ] && [ "$(cat $SIM/hostA/sudo-auth)" = ok ] && [ "$(wc -l < $SIM/hostA/reboots)" = 1 ]'
check "password never written to the state or host files" '! grep -rq sim-secret "$SIM/s12" "$SIM/hostA"'

reset_host
echo sim-secret | ctl s13 --secret-stdin run typed >/dev/null
check "secret_to_cmd: the command gets the password on its stdin" '[ $? = 0 ] && ! grep -rq sim-secret "$SIM/s13" "$SIM/hostA"'

# 14 a fresh state never reuses an old remote result of the same test/step
reset_host
ctl s14a run destr >/dev/null; ctl s14b run destr >/dev/null
check "fresh state runs again (own run ids)" '[ "$(wc -l < $SIM/hostA/counter)" = 2 ]'

echo "failures: $fails"
[ $fails = 0 ]
