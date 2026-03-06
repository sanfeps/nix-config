pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string ssid:       ""
    property int    strength:   0     // 0-100
    property string type:       ""    // "wifi", "ethernet", "disconnected"
    property bool   connected:  false

    property Timer _pollTimer: Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root._query()
    }

    property Process _proc: Process {
        id: nmcliProc
        // Get active connection info
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
        stdout: SplitParser {
            onRead: data => root._parseLine(data)
        }
        onRunningChanged: if (!running) root._querySignal()
    }

    property Process _signalProc: Process {
        id: signalProc
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SSID", "device", "wifi", "list"]
        stdout: SplitParser {
            onRead: data => root._parseSignal(data)
        }
    }

    function _query() {
        root.ssid      = ""
        root.connected = false
        root.type      = "disconnected"
        nmcliProc.running = false
        nmcliProc.running = true
    }

    function _parseLine(line: string) {
        var parts = line.split(":")
        if (parts.length < 3) return
        var devType = parts[0]
        var state   = parts[1]
        var conn    = parts[2]
        if (state === "connected") {
            root.connected = true
            root.type      = devType === "wifi" ? "wifi" : "ethernet"
            root.ssid      = conn
        }
    }

    function _querySignal() {
        if (root.type === "wifi") {
            signalProc.running = false
            signalProc.running = true
        }
    }

    function _parseSignal(line: string) {
        if (!line.startsWith("*:")) return
        var parts = line.split(":")
        if (parts.length >= 3) {
            root.strength = parseInt(parts[1]) || 0
        }
    }

    function icon(): string {
        if (!connected)             return "wifi_off"
        if (type === "ethernet")    return "lan"
        if (strength >= 75)         return "wifi"
        if (strength >= 50)         return "network_wifi_3_bar"
        if (strength >= 25)         return "network_wifi_2_bar"
        return "network_wifi_1_bar"
    }

    Component.onCompleted: _query()
}
