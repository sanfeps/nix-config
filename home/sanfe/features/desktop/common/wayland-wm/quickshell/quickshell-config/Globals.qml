pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Layout and Display Properties
    readonly property bool vertical: false
    readonly property string font: "Readex Pro"
    readonly property string secondaryFont: "Rubik"

    // Directory and Path Configuration
    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string cacheDir: Quickshell.env("XDG_CACHE_HOME") || homeDir + "/.cache"
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || homeDir + "/.config"
    readonly property string imageFolder: homeDir + "/Pictures/Wallpapers"

    // Date Management (updated by individual components as needed)
    readonly property var currentDate: new Date()

    // Color Palette - Based on Catppuccin Mocha with thorn-style adjustments
    readonly property var colors: {
        "colors": {
            // "color0": "1e1e2e",   // Base background
            "color0": "ffffff",   // Base background
            "color1": "f38ba8",   // Red
            "color2": "a6e3a1",   // Green
            "color3": "f9e2af",   // Yellow
            "color4": "89b4fa",   // Blue
            "color5": "cba6f7",   // Mauve
            "color6": "94e2d5",   // Teal
            "color7": "cdd6f4",   // Text
            "color8": "313244",   // Surface0
            "color9": "eba0ac",   // Maroon
            "color10": "a6e3a1",  // Green
            "color11": "f9e2af",  // Yellow
            "color12": "89b4fa",  // Blue
            "color13": "cba6f7",  // Mauve
            "color14": "94e2d5",  // Teal
            "color15": "cdd6f4"   // Text
        }
    }

    // Derived colors for easy access
    readonly property color backgroundColor: "#" + colors.colors.color0
    readonly property color backgroundAlt: "#" + colors.colors.color0  // Use same as backgroundColor
    readonly property color surfaceColor: "#45475a"
    readonly property color overlayColor: "#6c7086"

    readonly property color textColor: "#" + colors.colors.color7
    readonly property color textAlt: "#bac2de"
    readonly property color textDim: "#a6adc8"

    readonly property color accentColor: "#" + colors.colors.color4
    readonly property color accentAlt: "#74c7ec"
    readonly property color successColor: "#" + colors.colors.color2
    readonly property color warningColor: "#" + colors.colors.color3
    readonly property color errorColor: "#" + colors.colors.color1
    readonly property color specialColor: "#" + colors.colors.color5

    // Spacing and Layout
    readonly property int paddingSmall: 4
    readonly property int padding: 8
    readonly property int paddingLarge: 12
    readonly property int paddingXL: 16

    readonly property int spacing: 6
    readonly property int spacingLarge: 10

    // Border radius
    readonly property int radiusSmall: 4
    readonly property int radius: 6
    readonly property int radiusLarge: 8

    // Font sizes
    readonly property int fontSmall: 10
    readonly property int fontNormal: 12
    readonly property int fontLarge: 14
    readonly property int fontXL: 16
    readonly property int fontTitle: 18

    // Bar configuration
    readonly property int barHeight: 40
    readonly property int barPadding: 8
    readonly property int barSpacing: 10

    // Animations
    readonly property int animationDuration: 150
    readonly property int animationDurationSlow: 300

    // Opacity
    readonly property real opacityDim: 0.6
    readonly property real opacityDisabled: 0.4

    // Notification settings
    property bool notificationsEnabled: true

    // Function to reload colors (placeholder for future Walrus/Pywal integration)
    function reloadColors() {
        console.log("Reloading colors...")
    }
}
