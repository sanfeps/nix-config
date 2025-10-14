import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets" as Widgets
import "../.."

Scope {
    id: bar

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barRoot
            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:bar"
            implicitHeight: 32
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
            }

            // Main container
            Rectangle {
                anchors.fill: parent
                color: "#1e1e2e"  // Dark background

                // Subtle bottom border for depth
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: "#313244"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 12

                    // Left section - Workspaces
                    Widgets.Workspaces {
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Center section - Window Title
                    Widgets.WindowTitle {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Right section - System Tray
                    Widgets.NetworkInfo {
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
