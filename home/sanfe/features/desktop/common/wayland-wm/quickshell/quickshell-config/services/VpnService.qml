pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool active: false

    property Timer _pollTimer: Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root._query()
    }

    property Process _proc: Process {
        id: vpnProc
        command: ["sh", "-c", "ip link show wg0 2>/dev/null | grep -q 'UP' && echo 1 || echo 0"]
        stdout: SplitParser {
            onRead: data => root.active = (data.trim() === "1")
        }
    }

    function _query() {
        vpnProc.running = false
        vpnProc.running = true
    }

    Component.onCompleted: _query()
}
