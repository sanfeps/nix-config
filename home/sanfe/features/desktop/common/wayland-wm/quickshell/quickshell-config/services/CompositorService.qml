pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: root

    // Detected compositor
    readonly property bool isHyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
    readonly property bool isNiri:     Quickshell.env("NIRI_SOCKET") !== ""

    // Workspace data (unified API)
    property var workspaces:      []
    property int activeWorkspace: 1

    // Hyprland data (used when isHyprland)
    property Connections _hyprConn: Connections {
        target: isHyprland ? Hyprland : null
        enabled: isHyprland

        function onFocusedMonitorChanged() { root._syncHyprWorkspaces() }
        function onWorkspacesChanged()     { root._syncHyprWorkspaces() }
    }

    // Niri polling (fallback when !isHyprland)
    property Timer _niriTimer: Timer {
        interval: 500
        running: root.isNiri
        repeat: true
        onTriggered: root._queryNiri()
    }

    property Process _niriProc: Process {
        id: niriProc
        command: ["niri", "msg", "--json", "workspaces"]
        stdout: SplitParser {
            onRead: data => root._parseNiri(data)
        }
    }

    property string _niriAccum: ""

    function _queryNiri() {
        _niriAccum = ""
        niriProc.running = false
        niriProc.running = true
    }

    function _parseNiri(line: string) {
        _niriAccum += line
        try {
            var arr = JSON.parse(_niriAccum)
            var wsList = []
            var active = 1
            for (var i = 0; i < arr.length; i++) {
                wsList.push({ id: arr[i].idx + 1, name: String(arr[i].idx + 1), windows: 0 })
                if (arr[i].is_focused) active = arr[i].idx + 1
            }
            root.workspaces      = wsList
            root.activeWorkspace = active
        } catch (e) {}
    }

    function _syncHyprWorkspaces() {
        if (!isHyprland) return
        var wsList = []
        var wsArr = Hyprland.workspaces.values
        for (var i = 0; i < wsArr.length; i++) {
            var ws = wsArr[i]
            wsList.push({
                id:      parseInt(ws.name) || 0,
                name:    ws.name,
                windows: ws.windows ? ws.windows.length : 0
            })
        }
        root.workspaces = wsList
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace)
            root.activeWorkspace = parseInt(Hyprland.focusedMonitor.activeWorkspace.name) || 1
    }

    function switchWorkspace(id: int) {
        if (isHyprland) {
            Hyprland.dispatch("workspace " + id)
        } else if (isNiri) {
            var p = Qt.createQmlObject('import Quickshell.Io; Process{}', root)
            p.command = ["niri", "msg", "action", "focus-workspace", String(id)]
            p.running = true
        }
    }

    Component.onCompleted: {
        if (isHyprland) _syncHyprWorkspaces()
        if (isNiri)     _queryNiri()
    }
}
