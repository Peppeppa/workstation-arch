// FEATURE: wallpaper (see group_vars/all.yml wallpaper_enabled and
// docs/feature-architecture.md). Managed by Ansible: do not edit by hand,
// see roles/quickshell in workstation-arch.
//
// The desktop wallpaper: one background-layer surface per monitor, drawn
// by this Quickshell process (no separate wallpaper daemon). What to show
// comes from the active theme (Colors.data.wallpaper, rendered by the
// `theme` helper from themes/<id>/backgrounds/ + the per-theme choice) -
// updated by the same `theme reload` IPC as the colors, no file watcher.
//   none     the theme's background color
//   static   Image (PNG/JPEG/WebP), decoded at screen size
//   animated AnimatedImage (GIF, looping) - only loaded while an animated
//            wallpaper is selected
// Images are not kept in Qt's pixmap cache (cache: false), so switching
// frees the previous one.

import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: surface

            property var modelData
            readonly property var wallpaper: Colors.data.wallpaper || null
            readonly property string source: wallpaper ? "file://" + wallpaper.path : ""

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell-wallpaper"
            color: Colors.background

            Loader {
                anchors.fill: parent
                active: surface.wallpaper !== null && !surface.wallpaper.animated
                sourceComponent: Image {
                    source: surface.source
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: surface.width * surface.devicePixelRatio
                    sourceSize.height: surface.height * surface.devicePixelRatio
                    asynchronous: true
                    cache: false
                }
            }

            Loader {
                anchors.fill: parent
                active: surface.wallpaper !== null && surface.wallpaper.animated
                sourceComponent: AnimatedImage {
                    source: surface.source
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    playing: true
                }
            }
        }
    }
}
