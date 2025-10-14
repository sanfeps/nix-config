pragma Singleton
import QtQuick

QtObject {
    // Color Palette - Minimalist Dark Theme
    readonly property color bg: "#1e1e2e"           // Background
    readonly property color bgAlt: "#313244"        // Alternative background
    readonly property color surface: "#45475a"      // Surface
    readonly property color overlay: "#6c7086"      // Overlay

    readonly property color text: "#cdd6f4"         // Primary text
    readonly property color textAlt: "#bac2de"      // Secondary text
    readonly property color textDim: "#a6adc8"      // Dimmed text

    readonly property color accent: "#89b4fa"       // Accent blue
    readonly property color accentAlt: "#74c7ec"    // Alternative accent
    readonly property color success: "#a6e3a1"      // Success green
    readonly property color warning: "#f9e2af"      // Warning yellow
    readonly property color error: "#f38ba8"        // Error red
    readonly property color special: "#cba6f7"      // Special purple

    // Spacing
    readonly property int paddingSmall: 4
    readonly property int padding: 8
    readonly property int paddingLarge: 12
    readonly property int paddingXL: 16

    readonly property int spacing: 8
    readonly property int spacingLarge: 12

    // Border radius
    readonly property int radiusSmall: 4
    readonly property int radius: 8
    readonly property int radiusLarge: 12

    // Font sizes
    readonly property int fontSmall: 10
    readonly property int fontNormal: 12
    readonly property int fontLarge: 14
    readonly property int fontXL: 16
    readonly property int fontTitle: 20

    // Bar
    readonly property int barHeight: 32
    readonly property int barPadding: 6

    // Animations
    readonly property int animationDuration: 150
    readonly property int animationDurationSlow: 300

    // Opacity
    readonly property real opacityDim: 0.6
    readonly property real opacityDisabled: 0.4
}
