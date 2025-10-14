//@ pragma UseQApplication

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland

import "./modules/bar"
// import "./modules/launcher"  // Disabled for now
// import "./modules/notifications"  // Disabled for now

ShellRoot {
    id: root

    // Feature flags
    property bool enableBar: true
    property bool enableLauncher: false  // Disabled for now - needs fixing
    property bool enableNotifications: false  // Disabled for now

    // Load components
    LazyLoader {
        id: barLoader
        active: enableBar
        component: Bar {}
    }

    // Launcher and Notifications disabled temporarily - need fixing
    // LazyLoader {
    //     id: launcherLoader
    //     active: enableLauncher
    //     component: Launcher {
    //         id: launcher
    //     }
    // }

    // LazyLoader {
    //     id: notificationsLoader
    //     active: enableNotifications
    //     component: Notifications {
    //         id: notifications
    //     }
    // }

    // Global shortcuts handler (if needed)
    // This would require additional IPC integration with Hyprland
    // or using a service like swhkd for global shortcuts
}
