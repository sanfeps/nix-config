pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property real volume: 0.0        // 0.0–1.0
    property bool muted: false
    property string sinkName: ""

    // Poll volume every 2 seconds (and after explicit changes)
    property Timer _pollTimer: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root._queryVolume()
    }

    property Process _volProc: Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        stdout: SplitParser {
            onRead: data => root._parseVolume(data)
        }
    }

    function _queryVolume() {
        volProc.running = false
        volProc.running = true
    }

    function _parseVolume(line: string) {
        // Format: "Volume: 0.50" or "Volume: 0.50 [MUTED]"
        var match = line.match(/Volume:\s*([\d.]+)(\s*\[MUTED\])?/)
        if (match) {
            root.volume = parseFloat(match[1])
            root.muted  = !!match[2]
        }
    }

    function setVolume(pct: real) {
        var val = Math.max(0.0, Math.min(1.5, pct))
        _runCmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", val.toFixed(2)])
        root.volume = val
    }

    function toggleMute() {
        _runCmd(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        root.muted = !root.muted
    }

    function volumeUp() {
        _runCmd(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", "5%+"])
        root._queryVolume()
    }

    function volumeDown() {
        _runCmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"])
        root._queryVolume()
    }

    property Process _cmdProc: Process {
        id: cmdProc
    }

    function _runCmd(args: var) {
        cmdProc.command = args
        cmdProc.running = false
        cmdProc.running = true
    }

    function volumeIcon(): string {
        if (muted || volume <= 0.0) return "volume_off"
        if (volume < 0.33)          return "volume_down"
        if (volume < 0.66)          return "volume_up"
        return "volume_up"
    }

    Component.onCompleted: _queryVolume()
}
