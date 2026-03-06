import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".." as Root
import "widgets" as Widgets

Scope {
    id: bar

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barRoot
            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:bar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: Root.Theme.barHeight

            implicitHeight: Root.Theme.barHeight
            color: "transparent"

            anchors {
                top:   true
                left:  true
                right: true
            }

            // Bar background
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(
                    Root.Colors.surface.r,
                    Root.Colors.surface.g,
                    Root.Colors.surface.b,
                    0.88
                )

                // Bottom border accent
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    height: 1
                    color: Root.Colors.outlineVariant
                    opacity: 0.6
                }

                RowLayout {
                    anchors.fill:         parent
                    anchors.leftMargin:   Root.Theme.barPadding
                    anchors.rightMargin:  Root.Theme.barPadding
                    anchors.topMargin:    Root.Theme.spacingXs
                    anchors.bottomMargin: Root.Theme.spacingXs
                    spacing: Root.Theme.barSpacing

                    // ── Left section ──
                    RowLayout {
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: Root.Theme.barSpacing

                        Widgets.Workspaces { Layout.alignment: Qt.AlignVCenter }
                        Widgets.MediaMini  { Layout.alignment: Qt.AlignVCenter }
                    }

                    // ── Center: clock ──
                    Widgets.Clock {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // ── Right section ──
                    RowLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        spacing: Root.Theme.barSpacing

                        Widgets.AudioVisualizer { Layout.alignment: Qt.AlignVCenter }
                        Widgets.VPN       { Layout.alignment: Qt.AlignVCenter }
                        Widgets.Bluetooth { Layout.alignment: Qt.AlignVCenter }
                        Widgets.Network   { Layout.alignment: Qt.AlignVCenter }
                        Widgets.Battery   { Layout.alignment: Qt.AlignVCenter }
                        Widgets.Volume    { Layout.alignment: Qt.AlignVCenter }
                    }
                }
            }
        }
    }
}
