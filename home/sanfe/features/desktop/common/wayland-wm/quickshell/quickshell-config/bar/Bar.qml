import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "widgets" as Widgets
import ".." as Root

Scope {
    id: bar

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barRoot
            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:bar"
            implicitHeight: Root.Globals.barHeight
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
            }

            // Main bar container
            Rectangle {
                id: barBackground
                anchors.fill: parent
                color: "transparent"

                // Semi-transparent background with blur effect
                Rectangle {
                    anchors.fill: parent
                    color: Root.Globals.backgroundColor
                    opacity: 0.90
                }

                // Subtle bottom border
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Root.Globals.backgroundAlt
                    opacity: 0.3
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Root.Globals.barPadding
                    anchors.rightMargin: Root.Globals.barPadding
                    anchors.topMargin: Root.Globals.barPadding
                    anchors.bottomMargin: Root.Globals.barPadding
                    spacing: Root.Globals.barSpacing

                    // Left section
                    RowLayout {
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: Root.Globals.barSpacing

                        Widgets.PowerButton {
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Widgets.Workspaces {
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Widgets.MediaPlayer {
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    // Center section
                    Widgets.ActiveWindow {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Right section
                    RowLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        spacing: Root.Globals.barSpacing

                        Widgets.SystemTray {
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Widgets.Volume {
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Widgets.Clock {
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
