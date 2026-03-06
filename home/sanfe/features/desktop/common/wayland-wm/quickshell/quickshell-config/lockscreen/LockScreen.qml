import QtQuick
import Quickshell
import Quickshell.Wayland
import ".." as Root

Scope {
    id: lockScope

    SessionLock {
        id: sessionLock

        // Create a surface (panel) on every screen when locked
        Variants {
            model: sessionLock.locked ? Quickshell.screens : null

            SessionLockSurface {
                id: surface
                required property ShellScreen modelData
                screen: modelData

                // Full-screen lock surface
                LockBackground { anchors.fill: parent }

                LockPanel {
                    anchors.centerIn: parent
                    onUnlockSuccess: sessionLock.unlock()
                }
            }
        }
    }
}
