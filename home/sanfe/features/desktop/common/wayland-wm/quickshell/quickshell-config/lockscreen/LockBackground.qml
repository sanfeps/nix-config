import QtQuick
import QtQuick.Effects
import ".." as Root

Item {
    id: root

    // Dark overlay over wallpaper (swww manages the actual wallpaper)
    Rectangle {
        anchors.fill: parent
        color: Root.Colors.background
        opacity: 0.85
    }

    // Subtle animated gradient
    Rectangle {
        anchors.fill: parent
        opacity: 0.15
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Root.Colors.primaryContainer }
            GradientStop { position: 1.0; color: Root.Colors.background }
        }
    }
}
