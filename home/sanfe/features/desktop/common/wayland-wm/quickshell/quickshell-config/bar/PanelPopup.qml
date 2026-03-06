import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import ".." as Root

// Base floating panel anchored below the bar
PopupWindow {
    id: root

    property ShellScreen targetScreen: null
    property alias content: contentLoader.sourceComponent

    screen: targetScreen
    visible: false
    color: "transparent"

    // Position below the bar, on the right side
    anchors.right: true
    topMargin: Root.Theme.barHeight + Root.Theme.spacingSm

    Rectangle {
        id: panel
        anchors.fill: parent
        color: Root.Colors.surfaceContainerHigh
        radius: Root.Theme.radiusLg
        border.color: Root.Colors.outlineVariant
        border.width: 1

        // Drop shadow
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.8
            shadowColor: Qt.rgba(0, 0, 0, 0.4)
            shadowVerticalOffset: 4
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            anchors.margins: Root.Theme.spacingMd
        }
    }

    // Fade animation
    Behavior on opacity {
        NumberAnimation { duration: Root.Theme.animNormal; easing.type: Easing.OutCubic }
    }

    function show() {
        visible = true
        opacity = 1.0
    }

    function hide() {
        opacity = 0.0
        visible = false
    }
}
