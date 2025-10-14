import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../.."

Rectangle {
    id: battery

    property UPowerDevice primaryDevice: UPower.displayDevice

    visible: primaryDevice && primaryDevice.type !== UPowerDevice.Unknown

    Layout.preferredWidth: batteryLayout.width + (Theme.padding * 2)
    Layout.preferredHeight: Theme.barHeight - (Theme.barPadding * 2)
    radius: Theme.radius
    color: Theme.bgAlt

    RowLayout {
        id: batteryLayout
        anchors.centerIn: parent
        spacing: Theme.paddingSmall

        Text {
            text: {
                if (!primaryDevice) return ""

                var percentage = Math.round(primaryDevice.percentage)

                if (percentage >= 90) return ""
                else if (percentage >= 70) return ""
                else if (percentage >= 50) return ""
                else if (percentage >= 30) return ""
                else if (percentage >= 10) return ""
                else return ""
            }
            color: {
                if (!primaryDevice) return Theme.text

                var percentage = primaryDevice.percentage
                if (percentage <= 20) return Theme.error
                else if (percentage <= 50) return Theme.warning
                else return Theme.success
            }
            font.pixelSize: Theme.fontNormal
        }

        Text {
            text: primaryDevice ? Math.round(primaryDevice.percentage) + "%" : ""
            color: Theme.text
            font.pixelSize: Theme.fontSmall
        }

        Text {
            visible: primaryDevice && primaryDevice.state === UPowerDevice.Charging
            text: ""
            color: Theme.accent
            font.pixelSize: Theme.fontSmall
        }
    }
}
