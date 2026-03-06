import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".." as Root

Scope {
    id: osdScope

    // OSD shown on primary screen
    PanelWindow {
        id: osdWindow
        screen: Quickshell.screens[0] ?? null

        WlrLayershell.namespace: "quickshell:osd"
        WlrLayershell.layer:     WlrLayer.Overlay

        color:   "transparent"
        visible: osdVisible

        implicitWidth:  240
        implicitHeight: 60

        // Center on screen
        anchors {
            top:    false
            bottom: false
            left:   false
            right:  false
        }

        property bool osdVisible: false
        property string osdType:  "volume"   // "volume" | "brightness"
        property real   osdValue: 0.0        // 0.0–1.0

        opacity: osdVisible ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: Root.Theme.animFast }
        }

        Timer {
            id: hideTimer
            interval: 2000
            onTriggered: osdWindow.osdVisible = false
        }

        function show(type: string, value: real) {
            osdType    = type
            osdValue   = value
            osdVisible = true
            hideTimer.restart()
        }

        Rectangle {
            anchors.fill: parent
            radius: Root.Theme.radiusLg
            color: Qt.rgba(
                Root.Colors.surfaceContainerHigh.r,
                Root.Colors.surfaceContainerHigh.g,
                Root.Colors.surfaceContainerHigh.b,
                0.92
            )
            border.color: Root.Colors.outlineVariant
            border.width: 1

            RowLayout {
                anchors { fill: parent; margins: Root.Theme.spacingMd }
                spacing: Root.Theme.spacingMd

                Text {
                    text: osdWindow.osdType === "volume"
                        ? Root.AudioService.volumeIcon()
                        : "brightness_6"
                    font.family:    "Material Symbols Rounded"
                    font.pixelSize: Root.Theme.iconXl
                    color: Root.Colors.primary
                }

                // Progress bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: Root.Theme.radiusFull
                    color: Root.Colors.surfaceVariant

                    Rectangle {
                        width: parent.width * osdWindow.osdValue
                        height: parent.height
                        radius: parent.radius
                        color: Root.Colors.primary
                        Behavior on width { NumberAnimation { duration: Root.Theme.animFast } }
                    }
                }

                Text {
                    text: Math.round(osdWindow.osdValue * 100) + "%"
                    font.family:    Root.Theme.fontFamily
                    font.pixelSize: Root.Theme.fontSizeSm
                    color: Root.Colors.surfaceFg
                    Layout.minimumWidth: 36
                }
            }
        }
    }

    // Listen for volume changes via PulseAudio DBus property changes
    // (AudioService polls every 2s; OSD also watches for rapid changes)
    Connections {
        target: Root.AudioService
        function onVolumeChanged() {
            osdWindow.show("volume", Root.AudioService.volume)
        }
        function onMutedChanged() {
            osdWindow.show("volume", Root.AudioService.muted ? 0 : Root.AudioService.volume)
        }
    }
}
