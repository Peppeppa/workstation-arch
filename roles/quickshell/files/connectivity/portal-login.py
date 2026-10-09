#!/usr/bin/env python3
# FEATURE: connectivity (group_vars/all.yml connectivity_enabled). Managed
# by Ansible (roles/quickshell/files/connectivity/portal-login.py) - do not
# edit by hand.
#
# Opens a captive portal's login page: one Chromium window of its own,
# started by the Connectivity popup's "Log in" button and by PortalWatcher
# when NetworkManager reports connectivity "portal". Execs Chromium and is
# gone; nothing stays running once the window is closed.
#
# Why not simply `chromium <NM's ConnectivityCheckUri>` (the earlier way,
# real failure at @BayernWLAN 2026-10-09 - Chromium showed nothing at all):
# - Arch's check URL (ping.archlinux.org) is on Chromium's HSTS preload
#   list (archlinux.org, includeSubdomains): Chromium only ever requests it
#   over HTTPS, which a portal cannot redirect. The page opened here is
#   plain HTTP and not HSTS-preloaded: NetworkManager's own upstream check
#   endpoint, nmcheck.gnome.org (verified with a Chromium net-log: no HSTS
#   or HTTPS-Upgrades request).
# - The managed Chromium policy's PAC URL (roles/apps, the THWS library
#   proxy) must be fetched before any page loads; behind a portal that
#   silently drops it, the window stayed blank ~30 s (measured). Proxy
#   policy beats command-line proxy flags, so in THIS window the PAC hosts
#   resolve to NXDOMAIN instead (--host-resolver-rules): the PAC fails at
#   once and Chromium goes DIRECT (ProxyPacMandatory is off) - measured
#   0.7 s. The hosts are read from the policy files, nothing duplicated.
# - A separate profile (--user-data-dir) is a separate Chromium process:
#   a Chromium already running (web apps included) would otherwise take
#   the URL into one of its windows - possibly on another workspace - and
#   ignore every flag here. HTTPS-Upgrades are off in it for the same
#   reason as HSTS above. Profile = ~/.cache/workstation/portal-browser.
# - --disable-extensions: the policy's store extensions (roles/apps) would
#   otherwise be installed into this profile too and open their welcome
#   tabs over the portal page (measured on the first start).

import glob
import json
import os
import sys
from urllib.parse import urlsplit

PORTAL_URL = "http://nmcheck.gnome.org/check_network_status.txt"
POLICY_GLOB = "/etc/chromium/policies/managed/*.json"


def pac_hosts():
    hosts = set()
    for path in sorted(glob.glob(POLICY_GLOB)):
        try:
            with open(path, encoding="utf-8") as f:
                policy = json.load(f)
        except (OSError, ValueError):
            continue
        if not isinstance(policy, dict):
            continue
        settings = policy.get("ProxySettings")
        for url in (settings.get("ProxyPacUrl") if isinstance(settings, dict) else None,
                    policy.get("ProxyPacUrl")):
            if isinstance(url, str) and urlsplit(url).hostname:
                hosts.add(urlsplit(url).hostname)
    return sorted(hosts)


def main():
    cache = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    profile = os.path.join(cache, "workstation", "portal-browser")
    os.makedirs(profile, mode=0o700, exist_ok=True)
    argv = ["chromium", "--user-data-dir=" + profile, "--no-first-run",
            "--no-default-browser-check", "--disable-extensions",
            "--disable-features=HttpsUpgrades"]
    hosts = pac_hosts()
    if hosts:
        argv.append("--host-resolver-rules=" + ", ".join("MAP %s ~NOTFOUND" % h for h in hosts))
    argv += ["--new-window", PORTAL_URL]
    try:
        os.execvp(argv[0], argv)
    except OSError as e:
        print("portal-login: cannot start chromium: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
