import QtQuick
import Quickshell
import Quickshell.Wayland
import ".." as Root

Scope {
    id: lockScope

    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            LockBackground { anchors.fill: parent }

            LockPanel {
                anchors.centerIn: parent
                onUnlockSuccess: sessionLock.unlock()
            }
        }
    }
}
