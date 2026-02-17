//@ pragma UseQApplication

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import "bar" as Bar

ShellRoot {
    id: root

    // Thorn-inspired shell configuration
    Bar.Bar {
        id: topbar
    }

    // Initialize colors on startup
    Component.onCompleted: {
        console.log("Thorn-inspired QuickShell loaded")
        console.log("Using Globals singleton for theming")
    }
}
