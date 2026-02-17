import QtQuick

Rectangle {
    id: root

    property int padding: 3
    default property alias content: contentItem.data
    property alias widgetAnchors: contentItem.anchors

    implicitWidth: contentItem.implicitWidth + (padding * 2)
    implicitHeight: contentItem.implicitHeight + (padding * 2)

    color: "transparent"

    Item {
        id: contentItem
        anchors {
            fill: parent
            margins: padding
        }

        implicitWidth: {
            var maxWidth = 0;
            for (var i = 0; i < children.length; i++) {
                if (children[i].implicitWidth !== undefined) {
                    maxWidth = Math.max(maxWidth, children[i].implicitWidth);
                }
            }
            return maxWidth;
        }

        implicitHeight: {
            var maxHeight = 0;
            for (var i = 0; i < children.length; i++) {
                if (children[i].implicitHeight !== undefined) {
                    maxHeight = Math.max(maxHeight, children[i].implicitHeight);
                }
            }
            return maxHeight;
        }
    }
}
