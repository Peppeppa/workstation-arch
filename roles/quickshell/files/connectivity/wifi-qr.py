#!/usr/bin/env python3
# FEATURE: connectivity (group_vars/all.yml connectivity_enabled). Managed
# by Ansible (roles/quickshell/files/connectivity/wifi-qr.py) - do not edit
# by hand.
#
# Prints, as one JSON object {"svg": ..., "password": ...}, an SVG QR code
# for joining the Wi-Fi network that is active on the given interface
# (standard "WIFI:T:WPA;S:...;P:...;;" payload) and the same password the
# QR encodes (null for an open network) - one credential read for both.
# Run by the Connectivity popup only when the user asks to share; the JSON
# goes to stdout (a pipe to Quickshell, held in memory while shown).
#
# The password is read on demand from NetworkManager (GetSecrets over
# D-Bus - NM/polkit decide whether this session may read it) and passed
# to qrencode on its stdin: never in argv, never logged, never written to
# disk. Not supported (exit 2, nothing printed): enterprise (802.1X), WEP,
# OWE, and secrets NM does not hand out (e.g. "ask every time" / agent-
# owned). Exit 1: no active Wi-Fi connection or NM/qrencode error.

import json
import subprocess
import sys

from gi.repository import Gio, GLib

NM = "org.freedesktop.NetworkManager"


def call(bus, path, iface, method, args=None, reply=None):
    return bus.call_sync(NM, path, iface, method, args, reply, Gio.DBusCallFlags.NONE, 5000, None).unpack()


def prop(bus, path, iface, name):
    return call(bus, path, "org.freedesktop.DBus.Properties", "Get",
                GLib.Variant("(ss)", (iface, name)), GLib.VariantType("(v)"))[0]


def escape(s):
    for c in ("\\", ";", ",", "\"", ":"):
        s = s.replace(c, "\\" + c)
    return s


def main():
    if len(sys.argv) != 2:
        print("usage: wifi-qr <interface>", file=sys.stderr)
        return 1
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        dev = call(bus, "/org/freedesktop/NetworkManager", NM, "GetDeviceByIpIface",
                   GLib.Variant("(s)", (sys.argv[1],)), GLib.VariantType("(o)"))[0]
        active = prop(bus, dev, NM + ".Device", "ActiveConnection")
        if active == "/":
            return 1
        conn = prop(bus, active, NM + ".Connection.Active", "Connection")
        settings = call(bus, conn, NM + ".Settings.Connection", "GetSettings",
                        None, GLib.VariantType("(a{sa{sv}})"))[0]
    except GLib.Error as e:
        print("wifi-qr: NetworkManager: %s" % e.message, file=sys.stderr)
        return 1

    wifi = settings.get("802-11-wireless", {})
    ssid = bytes(wifi.get("ssid", b"")).decode("utf-8", "replace")
    if not ssid or wifi.get("mode", "infrastructure") != "infrastructure":
        return 1
    security = settings.get("802-11-wireless-security")
    if security is None:
        kind, password = "nopass", ""
    elif security.get("key-mgmt") in ("wpa-psk", "sae"):
        try:
            secrets = call(bus, conn, NM + ".Settings.Connection", "GetSecrets",
                           GLib.Variant("(s)", ("802-11-wireless-security",)),
                           GLib.VariantType("(a{sa{sv}})"))[0]
        except GLib.Error:
            return 2
        password = secrets.get("802-11-wireless-security", {}).get("psk", "")
        if not password:
            return 2
        kind = "WPA"
    else:
        return 2      # 802.1X / WEP / OWE: no clean shareable payload

    payload = "WIFI:T:%s;S:%s;%s%s;" % (kind, escape(ssid),
                                       "P:%s;" % escape(password) if password else "",
                                       "H:true;" if wifi.get("hidden") else "")
    try:
        result = subprocess.run(["qrencode", "-t", "SVG", "-m", "2", "-o", "-"],
                                input=payload.encode(), stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, check=False)
    except OSError:
        return 1
    if result.returncode != 0:
        return 1
    json.dump({"svg": result.stdout.decode("utf-8"), "password": password or None}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
