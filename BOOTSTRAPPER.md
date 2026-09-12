# Bootstrapper Development Guide

## Purpose

This repository defines a reproducible minimal Arch Linux desktop based on:

- Arch Linux
- systemd
- Hyprland
- Quickshell
- NetworkManager
- PipeWire
- WirePlumber
- BlueZ

The goal is not to create another distribution.

The goal is to maintain a small, understandable and reproducible desktop configuration that can turn a clean Arch Linux installation into the intended workstation environment.

The repository is the source of truth.

A manually configured development VM is never the source of truth.

---

# Core principle

A clean Arch installation must be transformable into the complete desktop by running this repository's bootstrap process.

Conceptually:

```text
Clean Arch
    |
    v
git clone
    |
    v
./bootstrap.sh
    |
    v
reboot
    |
    v
working workstation
