import QtQuick
import QtQuick.Layouts
import ".." as Root

Rectangle {
    id: root
    implicitWidth: 320
    implicitHeight: 200
    color: "transparent"

    Column {
        anchors { fill: parent; margins: Root.Theme.spacingLg }
        spacing: Root.Theme.spacingMd

        // Album art placeholder
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width:  120
            height: 120
            radius: Root.Theme.radiusMd
            color:  Root.Colors.surfaceVariant

            Image {
                anchors.fill: parent
                anchors.margins: 0
                source: Root.MediaService.artUrl
                fillMode: Image.PreserveAspectCrop
                visible: Root.MediaService.artUrl !== ""
                layer.enabled: true
                // Clip to rounded rect
                Rectangle {
                    anchors.fill: parent
                    radius: Root.Theme.radiusMd
                    color: "transparent"
                    border.color: Root.Colors.outline
                    border.width: 1
                }
            }

            Text {
                anchors.centerIn: parent
                visible: Root.MediaService.artUrl === ""
                text: "music_note"
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconXl
                color: Root.Colors.surfaceFgVariant
            }
        }

        // Track info
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Root.MediaService.trackTitle || "No track"
            font.family:    Root.Theme.fontFamilyAlt
            font.pixelSize: Root.Theme.fontSizeMd
            font.weight:    Font.Medium
            color: Root.Colors.surfaceFg
            elide: Text.ElideRight
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Root.MediaService.trackArtist || ""
            font.family:    Root.Theme.fontFamily
            font.pixelSize: Root.Theme.fontSizeSm
            color: Root.Colors.surfaceFgVariant
            elide: Text.ElideRight
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }

        // Controls
        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Root.Theme.spacingXl

            Repeater {
                model: [
                    { icon: "skip_previous", action: "prev"  },
                    { icon: Root.MediaService.playing ? "pause" : "play_arrow", action: "play" },
                    { icon: "skip_next",     action: "next"  }
                ]

                Text {
                    required property var modelData
                    text:              modelData.icon
                    font.family:       "Material Symbols Rounded"
                    font.pixelSize:    modelData.action === "play" ? Root.Theme.iconXl : Root.Theme.iconLg
                    color:             modelData.action === "play" ? Root.Colors.primary : Root.Colors.surfaceFg

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var a = parent.modelData.action
                            if      (a === "play") Root.MediaService.playPause()
                            else if (a === "next") Root.MediaService.next()
                            else                   Root.MediaService.previous()
                        }
                    }
                }
            }
        }
    }
}
