import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../" as QsRoot

Scope {
    id: notifications

    property var notificationList: []

    Variants {
        model: Quickshell.screens

        FloatingWindow {
            id: notificationWindow
            required property ShellScreen modelData
            screen: modelData

            visible: notificationList.length > 0
            color: "transparent"

            width: 400
            height: contentColumn.height

            anchor {
                window.screen: true
                rect.x: screen.width - width - Theme.paddingXL
                rect.y: Theme.barHeight + Theme.paddingXL
            }

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: Theme.spacing

                Repeater {
                    model: notificationList

                    Rectangle {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.preferredHeight: notifContent.height + (Theme.paddingLarge * 2)

                        color: Theme.bg
                        radius: Theme.radius
                        border.width: 1
                        border.color: {
                            if (modelData.urgency === "critical") return Theme.error
                            else if (modelData.urgency === "normal") return Theme.accent
                            else return Theme.overlay
                        }

                        // Slide in animation
                        opacity: 0
                        x: 50
                        Component.onCompleted: {
                            slideInAnimation.start()
                        }

                        ParallelAnimation {
                            id: slideInAnimation
                            NumberAnimation { target: parent; property: "opacity"; to: 1; duration: Theme.animationDuration }
                            NumberAnimation { target: parent; property: "x"; to: 0; duration: Theme.animationDuration; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            id: notifContent
                            anchors.fill: parent
                            anchors.margins: Theme.paddingLarge
                            spacing: Theme.spacing

                            // Icon
                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignTop
                                color: Theme.bgAlt
                                radius: Theme.radiusSmall

                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        if (parent.parent.parent.modelData.urgency === "critical") return ""
                                        else return ""
                                    }
                                    color: {
                                        if (parent.parent.parent.modelData.urgency === "critical") return Theme.error
                                        else return Theme.accent
                                    }
                                    font.pixelSize: Theme.fontTitle
                                }
                            }

                            // Content
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.paddingSmall

                                Text {
                                    text: parent.parent.parent.modelData.summary
                                    color: Theme.text
                                    font.pixelSize: Theme.fontNormal
                                    font.weight: Font.Bold
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                Text {
                                    visible: parent.parent.parent.modelData.body !== ""
                                    text: parent.parent.parent.modelData.body
                                    color: Theme.textAlt
                                    font.pixelSize: Theme.fontSmall
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: Qt.formatDateTime(parent.parent.parent.modelData.time, "hh:mm")
                                    color: Theme.textDim
                                    font.pixelSize: Theme.fontSmall
                                }
                            }

                            // Close button
                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignTop
                                color: closeMouseArea.containsMouse ? Theme.error : Theme.surface
                                radius: Theme.radiusSmall

                                Behavior on color {
                                    ColorAnimation { duration: Theme.animationDuration }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: ""
                                    color: Theme.text
                                    font.pixelSize: Theme.fontSmall
                                }

                                MouseArea {
                                    id: closeMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: {
                                        notifications.removeNotification(index)
                                    }
                                }
                            }
                        }

                        // Auto-dismiss timer
                        Timer {
                            interval: modelData.timeout || 5000
                            running: true
                            onTriggered: notifications.removeNotification(index)
                        }
                    }
                }
            }
        }
    }

    // Functions to manage notifications
    function addNotification(summary, body, urgency, timeout) {
        var notification = {
            summary: summary,
            body: body || "",
            urgency: urgency || "normal",
            timeout: timeout || 5000,
            time: new Date()
        }
        notificationList.push(notification)
        notificationListChanged()
    }

    function removeNotification(index) {
        notificationList.splice(index, 1)
        notificationListChanged()
    }

    // Example notifications for testing
    Component.onCompleted: {
        // You would typically connect this to a notification daemon
        // For now, here's an example of how to add a notification:
        // addNotification("Welcome", "QuickShell is running!", "normal", 5000)
    }
}
