#!/usr/bin/env python3
"""Fake ssh for testctl's simulations: runs the command locally in
$SIM/<host>/ (the fake host's home) and fails on demand.
Scenario $SIM/scenario.json: {"<host>": {"down": [call numbers -> 255],
"down_until": unix time, "lose_reply": [call numbers: run, then 255]}}."""
import json, os, subprocess, sys, time
sim = os.environ["SIM"]
args = sys.argv[1:]
cmd = args[-1]
host = args[-2]
sc_path = os.path.join(sim, "scenario.json")
try:
    sc = json.load(open(sc_path)).get(host, {})
except FileNotFoundError:
    sc = {}
home = os.path.join(sim, host.replace("alt-", ""))   # alt-X = second path to X
os.makedirs(home, exist_ok=True)
cnt_file = os.path.join(home, ".calls")
n = int(open(cnt_file).read()) + 1 if os.path.exists(cnt_file) else 1
open(cnt_file, "w").write(str(n))
if n in sc.get("down", []) or time.time() < sc.get("down_until", 0) or sc.get("dead"):
    print(f"ssh: connect to host {host}: Connection timed out", file=sys.stderr)
    sys.exit(255)
cmd = cmd.replace("/proc/sys/kernel/random/boot_id", os.path.join(home, "boot_id"))
p = subprocess.run(["bash", "-c", cmd], cwd=home, env={**os.environ, "HOME": home}, capture_output=True, text=True)
if n in sc.get("lose_reply", []):
    print("Connection reset by peer", file=sys.stderr)
    sys.exit(255)
sys.stdout.write(p.stdout); sys.stderr.write(p.stderr)
sys.exit(p.returncode)
