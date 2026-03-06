pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property int    capacity:   100
    property string status:     "Unknown"   // "Charging", "Discharging", "Full", "Unknown"
    property bool   charging:   false
    property bool   present:    false

    property FileView _capacityFile: FileView {
        path: "/sys/class/power_supply/BAT0/capacity"
        watchChanges: true
        onTextChanged: {
            var v = parseInt(text.trim())
            if (!isNaN(v)) root.capacity = v
        }
        Component.onCompleted: {
            var v = parseInt(text.trim())
            if (!isNaN(v)) root.capacity = v
        }
    }

    property FileView _statusFile: FileView {
        path: "/sys/class/power_supply/BAT0/status"
        watchChanges: true
        onTextChanged: root._updateStatus(text.trim())
        Component.onCompleted: root._updateStatus(text.trim())
    }

    property FileView _presentFile: FileView {
        path: "/sys/class/power_supply/BAT0/present"
        watchChanges: true
        onTextChanged: root.present = (text.trim() === "1")
        Component.onCompleted: root.present = (text.trim() === "1")
    }

    function _updateStatus(s: string) {
        root.status   = s
        root.charging = (s === "Charging")
    }

    function icon(): string {
        if (!present)  return "battery_unknown"
        if (charging)  return "battery_charging_full"
        if (capacity >= 90) return "battery_full"
        if (capacity >= 60) return "battery_5_bar"
        if (capacity >= 40) return "battery_4_bar"
        if (capacity >= 20) return "battery_3_bar"
        if (capacity >= 10) return "battery_2_bar"
        return "battery_1_bar"
    }
}
