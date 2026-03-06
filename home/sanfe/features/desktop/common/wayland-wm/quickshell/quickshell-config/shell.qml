//@ pragma UseQApplication

import QtQuick
import Quickshell
import "bar" as Bar
import "notification" as Notif
import "osd" as Osd
import "lockscreen" as Lock

ShellRoot {
    id: root

    Bar.Bar {}
    Notif.NotificationPopup {}
    Osd.OSD {}
    Lock.LockScreen {}

    Component.onCompleted: {
        console.log("QuickShell loaded")
    }
}
