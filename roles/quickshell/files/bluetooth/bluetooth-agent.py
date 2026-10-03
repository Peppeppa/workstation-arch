#!/usr/bin/env python3
# FEATURE: bluetooth (group_vars/all.yml bluetooth_enabled). Managed by
# Ansible (roles/quickshell/files/bluetooth/bluetooth-agent.py) - do not
# edit by hand.
#
# The desktop's BlueZ pairing agent (org.bluez.Agent1). NOT a daemon: the
# Quickshell Bluetooth popup starts it as a child process only when the
# user pairs a device, and it exits when that pairing is over (or after
# TIMEOUT_S, or when Quickshell closes its stdin). While no pairing runs
# there is no agent at all - BlueZ then refuses requests that would need
# one, so nothing pairs with this machine without the user starting it.
#
# Protocol (one JSON object per line) - stdout/stdin are pipes to
# Quickshell, nothing is written anywhere else; PINs/passkeys are never
# logged (stderr only ever gets non-secret error text):
#   out: {"event": "ready"}
#        {"event": "confirm",   "device": PATH, "passkey": "123456"}   reply: accept
#        {"event": "authorize", "device": PATH}                        reply: accept
#        {"event": "pin",       "device": PATH}                        reply: accept + value
#        {"event": "passkey",   "device": PATH}                        reply: accept + value
#        {"event": "display",   "device": PATH, "code": "123456"}      (no reply)
#        {"event": "cancel"}                                           (BlueZ cancelled)
#   in:  {"accept": true|false, "value": "..."}   - answers the pending request
#        {"quit": true}                           - pairing over, exit now
#
# Only BlueZ itself may call the agent: every method call is checked
# against the current owner of org.bluez on the system bus.

import json
import sys

from gi.repository import Gio, GLib

TIMEOUT_S = 60
AGENT_PATH = "/org/workstation/bluetooth/agent"
CAPABILITY = "KeyboardDisplay"   # we can show codes and take input

AGENT_XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""

REJECTED = "org.bluez.Error.Rejected"


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Agent:
    def __init__(self, bus, loop):
        self.bus = bus
        self.loop = loop
        self.pending = None          # (invocation, kind) awaiting the UI's answer

    # -- BlueZ -> agent ----------------------------------------------------
    def handle(self, conn, sender, path, iface, method, params, invocation):
        if not self.from_bluez(sender):
            invocation.return_dbus_error(REJECTED, "caller is not BlueZ")
            return
        args = params.unpack()
        if method == "Release":
            invocation.return_value(None)
            self.loop.quit()
        elif method == "Cancel":
            self.reject_pending()
            emit({"event": "cancel"})
            invocation.return_value(None)
        elif method == "DisplayPinCode":
            emit({"event": "display", "device": args[0], "code": args[1]})
            invocation.return_value(None)
        elif method == "DisplayPasskey":
            emit({"event": "display", "device": args[0], "code": "%06d" % args[1]})
            invocation.return_value(None)
        elif method == "AuthorizeService":
            # Only runs during a user-started pairing: the device the user
            # chose may set up its services.
            invocation.return_value(None)
        else:
            kind = {"RequestConfirmation": "confirm", "RequestAuthorization": "authorize",
                    "RequestPinCode": "pin", "RequestPasskey": "passkey"}[method]
            self.reject_pending()                 # one question at a time
            self.pending = (invocation, kind)
            event = {"event": kind, "device": args[0]}
            if kind == "confirm":
                event["passkey"] = "%06d" % args[1]
            emit(event)

    def from_bluez(self, sender):
        try:
            owner = self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                       "org.freedesktop.DBus", "GetNameOwner",
                                       GLib.Variant("(s)", ("org.bluez",)), GLib.VariantType("(s)"),
                                       Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
        except GLib.Error:
            return False
        return sender == owner

    def reject_pending(self):
        if self.pending:
            self.pending[0].return_dbus_error(REJECTED, "superseded")
            self.pending = None

    # -- UI -> agent -------------------------------------------------------
    def on_stdin(self, channel, condition):
        line = channel.readline()
        if not line:                              # Quickshell closed stdin / went away
            self.loop.quit()
            return False
        try:
            msg = json.loads(line)
        except ValueError:
            return True
        if msg.get("quit"):
            self.loop.quit()
            return False
        if self.pending:
            invocation, kind = self.pending
            self.pending = None
            value = str(msg.get("value", ""))
            if not msg.get("accept"):
                invocation.return_dbus_error(REJECTED, "rejected by user")
            elif kind == "pin":
                invocation.return_value(GLib.Variant("(s)", (value,)))
            elif kind == "passkey":
                if value.isdigit() and int(value) <= 999999:
                    invocation.return_value(GLib.Variant("(u)", (int(value),)))
                else:
                    invocation.return_dbus_error(REJECTED, "invalid passkey")
            else:
                invocation.return_value(None)
        return True


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    loop = GLib.MainLoop()
    agent = Agent(bus, loop)
    info = Gio.DBusNodeInfo.new_for_xml(AGENT_XML).interfaces[0]
    reg = bus.register_object(AGENT_PATH, info, agent.handle, None, None)

    def manager(method, args):
        bus.call_sync("org.bluez", "/org/bluez", "org.bluez.AgentManager1", method,
                      args, None, Gio.DBusCallFlags.NONE, 5000, None)

    try:
        manager("RegisterAgent", GLib.Variant("(os)", (AGENT_PATH, CAPABILITY)))
        manager("RequestDefaultAgent", GLib.Variant("(o)", (AGENT_PATH,)))
    except GLib.Error as e:
        print("bluetooth-agent: cannot register with BlueZ: %s" % e.message, file=sys.stderr)
        return 1

    stdin = GLib.IOChannel.unix_new(sys.stdin.fileno())
    GLib.io_add_watch(stdin, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, agent.on_stdin)
    GLib.timeout_add_seconds(TIMEOUT_S, loop.quit)
    emit({"event": "ready"})
    loop.run()

    agent.reject_pending()
    try:
        manager("UnregisterAgent", GLib.Variant("(o)", (AGENT_PATH,)))
    except GLib.Error:
        pass
    bus.unregister_object(reg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
