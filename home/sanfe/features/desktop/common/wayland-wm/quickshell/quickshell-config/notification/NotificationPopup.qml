import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import ".." as Root

Scope {
    id: notifScope

    // Notification server — registers on the DBus session bus
    NotificationServer {
        id: server
        keepOnReload: true
        // actionsSupported, bodySupported, etc. are true by default
    }

    // One layer-shell popup window per screen, anchored top-right
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:notification"
            WlrLayershell.layer:     WlrLayer.Overlay
            WlrLayershell.margins.top:   Root.Theme.barHeight + Root.Theme.spacingMd
            WlrLayershell.margins.right: Root.Theme.spacingMd

            color: "transparent"
            implicitWidth:  360
            implicitHeight: notifColumn.implicitHeight + Root.Theme.spacingMd * 2

            anchors {
                top:   true
                right: true
            }

            Column {
                id: notifColumn
                anchors {
                    left:   parent.left
                    right:  parent.right
                    top:    parent.top
                    topMargin: Root.Theme.spacingMd
                }
                spacing: Root.Theme.spacingSm

                Repeater {
                    // Show only the most recent 5 notifications
                    model: {
                        var notifs = server.notifications
                        return notifs.slice(Math.max(0, notifs.length - 5))
                    }

                    delegate: NotificationCard {
                        required property var modelData
                        notification: modelData
                        anchors { left: parent.left; right: parent.right }
                    }
                }
            }
        }
    }

    // Internal notification card component
    component NotificationCard: Rectangle {
        id: card
        property QtObject notification: null

        implicitHeight: cardRow.implicitHeight + Root.Theme.spacingMd * 2
        radius: Root.Theme.radiusLg
        color: Root.Colors.surfaceContainerHigh
        border.color: Root.Colors.outlineVariant
        border.width: 1
        opacity: 1.0
        clip: true

        // Auto-dismiss timer (uses notification's expiry or 6s default)
        Timer {
            id: dismissTimer
            interval: (card.notification && card.notification.expireTimeout > 0)
                ? card.notification.expireTimeout
                : 6000
            running: true
            onTriggered: {
                if (card.notification) card.notification.dismiss()
            }
        }

        // Swipe-to-dismiss
        property real _dragX: 0
        transform: Translate { x: card._dragX }

        DragHandler {
            id: drag
            xAxis.enabled: true
            yAxis.enabled: false
            onActiveChanged: {
                if (!active) {
                    if (Math.abs(card._dragX) > 80)
                        card.notification.dismiss()
                    else {
                        card._dragX = 0
                    }
                }
            }
        }

        Binding { target: card; property: "_dragX"; value: drag.active ? drag.translation.x : card._dragX }

        Behavior on _dragX {
            NumberAnimation { duration: Root.Theme.animFast; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: Root.Theme.animNormal }
        }

        RowLayout {
            id: cardRow
            anchors {
                left:   parent.left
                right:  parent.right
                top:    parent.top
                margins: Root.Theme.spacingMd
            }
            spacing: Root.Theme.spacingMd

            // App icon
            Rectangle {
                width:  36
                height: 36
                radius: Root.Theme.radiusMd
                color:  Root.Colors.primaryContainer

                Text {
                    anchors.centerIn: parent
                    text: "notifications"
                    font.family:    "Material Symbols Rounded"
                    font.pixelSize: Root.Theme.iconMd
                    color: Root.Colors.primaryFgContainer
                }
            }

            // Content
            Column {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: card.notification ? (card.notification.appName || "") : ""
                    font.family:    Root.Theme.fontFamily
                    font.pixelSize: Root.Theme.fontSizeXs
                    color: Root.Colors.surfaceFgVariant
                }

                Text {
                    text: card.notification ? (card.notification.summary || "") : ""
                    font.family:    Root.Theme.fontFamily
                    font.pixelSize: Root.Theme.fontSizeSm
                    font.weight:    Font.Medium
                    color: Root.Colors.surfaceFg
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    visible: card.notification && card.notification.body !== ""
                    text: card.notification ? (card.notification.body || "") : ""
                    font.family:    Root.Theme.fontFamily
                    font.pixelSize: Root.Theme.fontSizeXs
                    color: Root.Colors.surfaceFgVariant
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            // Close button
            Text {
                text: "close"
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconSm
                color: Root.Colors.surfaceFgVariant
                Layout.alignment: Qt.AlignTop

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.notification.dismiss()
                }
            }
        }

        // Slide in from right
        NumberAnimation on x {
            from:     parent.width
            to:       0
            duration: Root.Theme.animNormal
            easing.type: Easing.OutCubic
            running: true
        }
    }
}
