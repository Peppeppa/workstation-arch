#!/usr/bin/env python3
"""Minimal StatusNotifierItem + DBusMenu test client (System Tray v1).

Development/regression tool only - never deployed, never a service. Run it
by hand inside the desktop session; it registers one tray item with the
running StatusNotifierWatcher (Quickshell's), prints every interaction it
receives, and disappears from the tray when it exits (Ctrl+C / SIGTERM).

    scripts/sni-test-client.py [--name NAME] [--icon-name ICON | --pixmap RRGGBB]
                               [--status Active|Passive|NeedsAttention]

Logged events (stdout, one per line, flushed):
    Activate x y | SecondaryActivate x y | Scroll delta orientation |
    MenuEvent <label> <event> | ...

Uses only python-gobject (Gio/GLib), already on the system - no extra
packages. The menu exercises every DBusMenu feature the tray renders:
normal / disabled entries, a separator, a checkbox, a radio group and a
submenu.
"""

import argparse
import os
import signal
import sys

from gi.repository import Gio, GLib

SNI_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
    <signal name="NewIcon"/>
    <signal name="NewStatus"><arg type="s"/></signal>
    <signal name="NewToolTip"/>
  </interface>
</node>
"""

MENU_XML = """
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <method name="GetLayout">
      <arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/>
      <arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/>
    </method>
    <method name="Event">
      <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/>
    </method>
    <method name="EventGroup">
      <arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/>
    </method>
    <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
    <method name="AboutToShowGroup">
      <arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/>
    </method>
    <signal name="ItemsPropertiesUpdated"><arg type="a(ia{sv})"/><arg type="a(ia{s})"/></signal>
    <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
  </interface>
</node>
"""

ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"


def log(*parts):
    print(*parts, flush=True)


class Menu:
    """id -> (props, children). id 0 is the root."""

    def __init__(self):
        self.revision = 1
        self.items = {
            0: ({"children-display": GLib.Variant("s", "submenu")}, [1, 2, 3, 4, 5, 6, 7]),
            1: ({"label": GLib.Variant("s", "_Action A")}, []),
            2: ({"label": GLib.Variant("s", "Disabled entry"), "enabled": GLib.Variant("b", False)}, []),
            3: ({"type": GLib.Variant("s", "separator")}, []),
            4: ({"label": GLib.Variant("s", "Check me"), "toggle-type": GLib.Variant("s", "checkmark"),
                 "toggle-state": GLib.Variant("i", 1)}, []),
            5: ({"label": GLib.Variant("s", "Radio one"), "toggle-type": GLib.Variant("s", "radio"),
                 "toggle-state": GLib.Variant("i", 1)}, []),
            6: ({"label": GLib.Variant("s", "Radio two"), "toggle-type": GLib.Variant("s", "radio"),
                 "toggle-state": GLib.Variant("i", 0)}, []),
            7: ({"label": GLib.Variant("s", "More"), "children-display": GLib.Variant("s", "submenu")}, [8]),
            8: ({"label": GLib.Variant("s", "Nested action")}, []),
        }

    def layout(self, item_id, depth):
        props, children = self.items[item_id]
        kids = []
        if depth != 0:
            kids = [self.layout(c, depth - 1) for c in children]
        return GLib.Variant("(ia{sv}av)", (item_id, props, kids))

    def label(self, item_id):
        props = self.items.get(item_id, ({}, []))[0]
        return props["label"].unpack() if "label" in props else "#%d" % item_id


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--name", default="sni-test")
    ap.add_argument("--icon-name", default="")
    ap.add_argument("--pixmap", default="", help="RRGGBB: solid 22x22 icon pixmap instead of a theme icon")
    ap.add_argument("--status", default="Active")
    args = ap.parse_args()

    menu = Menu()
    pixmaps = []
    if args.pixmap:
        r, g, b = (int(args.pixmap[i:i + 2], 16) for i in (0, 2, 4))
        pixmaps = [(22, 22, bytes([255, r, g, b]) * 22 * 22)]  # ARGB32, network byte order
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    service = "org.kde.StatusNotifierItem-%d-1" % os.getpid()

    def sni_get(conn, sender, path, iface, prop):
        values = {
            "Category": GLib.Variant("s", "ApplicationStatus"),
            "Id": GLib.Variant("s", args.name),
            "Title": GLib.Variant("s", "%s title" % args.name),
            "Status": GLib.Variant("s", args.status),
            "WindowId": GLib.Variant("i", 0),
            "IconName": GLib.Variant("s", args.icon_name),
            "IconPixmap": GLib.Variant("a(iiay)", pixmaps),
            "OverlayIconName": GLib.Variant("s", ""),
            "AttentionIconName": GLib.Variant("s", ""),
            "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], "%s tooltip" % args.name, "SNI test client")),
            "ItemIsMenu": GLib.Variant("b", False),
            "Menu": GLib.Variant("o", MENU_PATH),
        }
        return values.get(prop)

    def sni_call(conn, sender, path, iface, method, params, invocation):
        log(method, *params.unpack())
        invocation.return_value(None)

    def menu_get(conn, sender, path, iface, prop):
        return {"Version": GLib.Variant("u", 3), "TextDirection": GLib.Variant("s", "ltr"),
                "Status": GLib.Variant("s", "normal"), "IconThemePath": GLib.Variant("as", [])}.get(prop)

    def menu_call(conn, sender, path, iface, method, params, invocation):
        p = params.unpack()
        if method == "GetLayout":
            invocation.return_value(GLib.Variant.new_tuple(GLib.Variant("u", menu.revision), menu.layout(p[0], p[1])))
        elif method == "GetGroupProperties":
            ids = p[0] or list(menu.items)
            invocation.return_value(GLib.Variant("(a(ia{sv}))", ([(i, menu.items[i][0]) for i in ids if i in menu.items],)))
        elif method == "GetProperty":
            invocation.return_value(GLib.Variant("(v)", (menu.items[p[0]][0][p[1]],)))
        elif method == "Event":
            item_id, event = p[0], p[1]
            log("MenuEvent", repr(menu.label(item_id)), event)
            if event == "clicked" and item_id == 4:  # toggle the checkbox, like a real app
                props = menu.items[4][0]
                props["toggle-state"] = GLib.Variant("i", 0 if props["toggle-state"].unpack() else 1)
                menu.revision += 1
                conn.emit_signal(None, MENU_PATH, "com.canonical.dbusmenu", "LayoutUpdated",
                                 GLib.Variant("(ui)", (menu.revision, 0)))
            invocation.return_value(None)
        elif method == "EventGroup":
            for item_id, event, _data, _ts in p[0]:
                log("MenuEvent", repr(menu.label(item_id)), event)
            invocation.return_value(GLib.Variant("(ai)", ([],)))
        elif method == "AboutToShow":
            invocation.return_value(GLib.Variant("(b)", (False,)))
        elif method == "AboutToShowGroup":
            invocation.return_value(GLib.Variant("(aiai)", ([], [])))
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

    sni_info = Gio.DBusNodeInfo.new_for_xml(SNI_XML).interfaces[0]
    menu_info = Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0]
    bus.register_object(ITEM_PATH, sni_info, sni_call, sni_get, None)
    bus.register_object(MENU_PATH, menu_info, menu_call, menu_get, None)
    Gio.bus_own_name_on_connection(bus, service, Gio.BusNameOwnerFlags.NONE, None, None)

    def register():
        bus.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                      "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
                      GLib.Variant("(s)", (service,)), None, Gio.DBusCallFlags.NONE, 3000, None)
        log("registered", service)
        return False

    loop = GLib.MainLoop()
    GLib.idle_add(register)
    for sig in (signal.SIGINT, signal.SIGTERM):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, loop.quit)
    loop.run()
    log("exiting")


if __name__ == "__main__":
    sys.exit(main())
