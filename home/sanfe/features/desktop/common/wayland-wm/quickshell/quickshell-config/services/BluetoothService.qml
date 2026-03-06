pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property bool   powered:     false
    property bool   connected:   false
    property string deviceName:  ""

    property Timer _pollTimer: Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: root._query()
    }

    property Process _proc: Process {
        id: btProc
        command: ["bluetoothctl", "show"]
        stdout: SplitParser {
            onRead: data => root._parsePowered(data)
        }
    }

    property Process _devProc: Process {
        id: btDevProc
        command: ["bluetoothctl", "info"]
        stdout: SplitParser {
            onRead: data => root._parseConnected(data)
        }
    }

    function _query() {
        btProc.running = false
        btProc.running = true
        btDevProc.running = false
        btDevProc.running = true
    }

    function _parsePowered(line: string) {
        if (line.includes("Powered: yes"))  root.powered = true
        if (line.includes("Powered: no"))   root.powered = false
    }

    function _parseConnected(line: string) {
        if (line.includes("Connected: yes"))  root.connected = true
        if (line.includes("Connected: no"))   root.connected = false
        var nameMatch = line.match(/^\s*Name:\s*(.+)$/)
        if (nameMatch) root.deviceName = nameMatch[1].trim()
    }

    function icon(): string {
        if (!powered)   return "bluetooth_disabled"
        if (connected)  return "bluetooth_connected"
        return "bluetooth"
    }

    function togglePower() {
        var cmd = powered ? "off" : "on"
        var p = Qt.createQmlObject('import Quickshell.Io; Process{}', root)
        p.command = ["bluetoothctl", cmd]
        p.running = true
        root.powered = !root.powered
    }

    Component.onCompleted: _query()
}
