import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../.."

Rectangle {
    id: network

    Layout.preferredWidth: networkLayout.width + (Theme.padding * 2)
    Layout.preferredHeight: Theme.barHeight - (Theme.barPadding * 2)
    radius: Theme.radius
    color: Theme.bgAlt

    // Simple network indicator - you can enhance this with NetworkManager integration
    RowLayout {
        id: networkLayout
        anchors.centerIn: parent
        spacing: Theme.paddingSmall

        Text {
            // This is a placeholder - in production you'd want to read actual network status
            text: ""
            color: Theme.success
            font.pixelSize: Theme.fontNormal
        }

        Text {
            text: "Connected"
            color: Theme.textAlt
            font.pixelSize: Theme.fontSmall
        }
    }
}
