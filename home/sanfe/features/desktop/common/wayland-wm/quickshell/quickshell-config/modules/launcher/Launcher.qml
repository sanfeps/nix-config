import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../../" as QsRoot

Scope {
    id: launcher

    property bool visible: false

    Variants {
        model: Quickshell.screens

        FloatingWindow {
            id: launcherWindow
            required property ShellScreen modelData
            screen: modelData

            visible: launcher.visible
            color: "transparent"

            width: 600
            height: 400
            x: (screen.width - width) / 2
            y: (screen.height - height) / 2

            Rectangle {
                anchors.fill: parent
                color: Theme.bg
                radius: Theme.radiusLarge
                border.width: 1
                border.color: Theme.accent

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.paddingXL
                    spacing: Theme.spacingLarge

                    // Search input
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        color: Theme.bgAlt
                        radius: Theme.radius

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.padding
                            spacing: Theme.spacing

                            Text {
                                text: ""
                                color: Theme.accent
                                font.pixelSize: Theme.fontLarge
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                color: Theme.text
                                font.pixelSize: Theme.fontNormal
                                selectByMouse: true

                                Text {
                                    visible: parent.text === ""
                                    text: "Search applications..."
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fontNormal
                                }

                                Keys.onEscapePressed: launcher.visible = false
                                Keys.onReturnPressed: {
                                    if (appsList.currentIndex >= 0) {
                                        launchApp(appsList.currentIndex)
                                    }
                                }
                                Keys.onDownPressed: {
                                    if (appsList.currentIndex < appsList.count - 1) {
                                        appsList.currentIndex++
                                    }
                                }
                                Keys.onUpPressed: {
                                    if (appsList.currentIndex > 0) {
                                        appsList.currentIndex--
                                    }
                                }

                                Component.onCompleted: forceActiveFocus()
                            }
                        }
                    }

                    // Application list
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        ListView {
                            id: appsList
                            model: appsModel
                            spacing: Theme.paddingSmall

                            delegate: Rectangle {
                                width: appsList.width
                                height: 50
                                color: ListView.isCurrentItem ? Theme.accent : (mouseArea.containsMouse ? Theme.surface : "transparent")
                                radius: Theme.radius

                                Behavior on color {
                                    ColorAnimation { duration: Theme.animationDuration }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.padding
                                    spacing: Theme.spacing

                                    Text {
                                        text: ""
                                        color: ListView.isCurrentItem ? Theme.bg : Theme.accent
                                        font.pixelSize: Theme.fontXL
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: modelData.name
                                            color: ListView.isCurrentItem ? Theme.bg : Theme.text
                                            font.pixelSize: Theme.fontNormal
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            text: modelData.description || ""
                                            color: ListView.isCurrentItem ? Theme.bg : Theme.textDim
                                            font.pixelSize: Theme.fontSmall
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: mouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: launchApp(index)
                                    onEntered: appsList.currentIndex = index
                                }
                            }
                        }
                    }
                }
            }

            // Close on click outside
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: launcher.visible = false
            }
        }
    }

    // Applications model - placeholder
    property var appsModel: [
        { name: "Firefox", description: "Web Browser", exec: "firefox" },
        { name: "Terminal", description: "Terminal Emulator", exec: "kitty" },
        { name: "Files", description: "File Manager", exec: "nautilus" },
        { name: "Settings", description: "System Settings", exec: "gnome-control-center" },
        { name: "Calculator", description: "Calculator", exec: "gnome-calculator" }
    ]

    function launchApp(index) {
        if (index < 0 || index >= appsModel.length) return

        var app = appsModel[index]
        Qt.createQmlObject(
            'import Quickshell.Io; Process { running: true; command: ["' + app.exec + '"] }',
            launcher
        )
        launcher.visible = false
    }

    // Global keybind handler would be set up in shell.qml
}
