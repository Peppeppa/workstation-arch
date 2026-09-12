# Architecture

Short, authoritative summary of the system-wide rules. Detailed
per-subsystem rationale lives in `docs/system_architecture.md`; this file
must not contradict it.

## Stack

```
Arch Linux
    ↓
Linux kernel / DRM-KMS
    ↓
Mesa
    ↓
Wayland
    ↓
Hyprland
    ↓
Quickshell
```

`docs/wifi_applet.md` and future subsystem docs describe individual
pieces of the `Quickshell` layer in more detail.

## One owner per responsibility

- NetworkManager owns networking state.
- PipeWire/WirePlumber own audio state.
- BlueZ owns Bluetooth state.
- Quickshell owns presentation - it displays and controls the above, it
  never becomes a second source of truth for them.

No two components compete for the same responsibility (e.g. no second
network manager, no second notification daemon, no duplicate autostart
mechanism for the same process).

## Event-driven, not polling

Backends emit events (D-Bus signals where available); Quickshell reacts.
Polling is allowed only where no reasonable event interface exists, and
should be bound to UI visibility (e.g. stop when a panel closes) rather
than running permanently.

## Idle stays quiet

No unnecessary background wakeups, no permanent diagnostic processes, no
continuous animation. Minimal permanent polling is a hard requirement,
not an optimization to get to later.

## Omarchy Quattro is a reference, not a dependency

Omarchy Quattro is used as a UX and code reference where it already
solves a problem well. The finished system must not require an Omarchy
installation to function - anything reused is vendored, adapted, and
documented, or replaced by a direct upstream dependency.

## Responsiveness is a primary design constraint

Instant interaction takes priority over decorative animation. Reliable,
proven upstream components take priority over clever custom
replacements. See `docs/system_architecture.md` §74 for the full
trade-off ordering.

## Public bootstrap, private secrets

See `BOOTSTRAPPER.md`. This repository is public and contains no
secrets; private, machine-specific credentials come from a separate
private repository, only once a credential provider is configured.
