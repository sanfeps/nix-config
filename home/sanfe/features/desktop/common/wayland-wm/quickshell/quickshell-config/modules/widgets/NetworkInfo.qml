import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."

Rectangle {
    id: network

    property string ipAddress: ""
    property string connectionType: "disconnected"
    property bool isVpnActive: false

    implicitWidth: networkLayout.implicitWidth + 16
    implicitHeight: 24
    Layout.alignment: Qt.AlignVCenter
    radius: 6
    color: "#313244"

    // Check IP address
    Process {
        id: ipProcess
        running: true
        command: ["bash", "-c", "ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \\K\\S+' || echo 'N/A'"]

        stdout: SplitParser {
            onRead: data => {
                network.ipAddress = data.trim()
            }
        }
    }

    // Check connection type (wifi/ethernet)
    Process {
        id: connectionProcess
        running: true
        command: ["bash", "-c", "ip route | grep default | awk '{print $5}' | head -1"]

        stdout: SplitParser {
            onRead: data => {
                var iface = data.trim()
                if (iface.startsWith("wl")) {
                    network.connectionType = "wifi"
                } else if (iface.startsWith("en") || iface.startsWith("eth")) {
                    network.connectionType = "ethernet"
                } else if (iface !== "") {
                    network.connectionType = "connected"
                } else {
                    network.connectionType = "disconnected"
                }
            }
        }
    }

    // Check for VPN (tun/wg interfaces)
    Process {
        id: vpnProcess
        running: true
        command: ["bash", "-c", "ip link show | grep -E 'tun|wg|vpn' | wc -l"]

        stdout: SplitParser {
            onRead: data => {
                network.isVpnActive = parseInt(data.trim()) > 0
            }
        }
    }

    // Refresh every 5 seconds
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            ipProcess.running = true
            connectionProcess.running = true
            vpnProcess.running = true
        }
    }

    RowLayout {
        id: networkLayout
        anchors.centerIn: parent
        spacing: 6

        // Connection icon
        Text {
            text: {
                if (connectionType === "wifi") return "󰖩"
                else if (connectionType === "ethernet") return "󰈀"
                else if (connectionType === "connected") return "󰌘"
                else return "󰌙"
            }
            color: connectionType === "disconnected" ? "#f38ba8" : "#a6e3a1"
            font.pixelSize: 13
        }

        // VPN indicator
        Text {
            visible: isVpnActive
            text: "󰦝"
            color: "#89b4fa"
            font.pixelSize: 11
        }

        // IP address (tooltip on hover)
        Text {
            text: ipAddress !== "N/A" && ipAddress !== "" ? ipAddress : "No IP"
            color: "#bac2de"
            font.pixelSize: 11
        }
    }

    // Clickable for future actions
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: parent.opacity = 0.8
        onExited: parent.opacity = 1.0
    }
}
