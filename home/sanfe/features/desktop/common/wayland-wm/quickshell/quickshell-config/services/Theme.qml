pragma Singleton
import QtQuick

QtObject {
    id: root

    // Fonts
    readonly property string fontFamily:       "Readex Pro"
    readonly property string fontFamilyAlt:    "Rubik"
    readonly property string fontFamilyMono:   "FiraMono Nerd Font Mono"

    // Font sizes
    readonly property int fontSizeXs:    10
    readonly property int fontSizeSm:    11
    readonly property int fontSizeMd:    12
    readonly property int fontSizeLg:    14
    readonly property int fontSizeXl:    16
    readonly property int fontSizeTitle: 20

    // Spacing
    readonly property int spacingXs:  4
    readonly property int spacingSm:  6
    readonly property int spacingMd:  8
    readonly property int spacingLg:  12
    readonly property int spacingXl:  16
    readonly property int spacingXxl: 24

    // Border radius
    readonly property int radiusXs: 4
    readonly property int radiusSm: 6
    readonly property int radiusMd: 8
    readonly property int radiusLg: 12
    readonly property int radiusXl: 16
    readonly property int radiusFull: 999

    // Bar
    readonly property int barHeight:  44
    readonly property int barPadding: 8
    readonly property int barSpacing: 6

    // Animation durations (ms)
    readonly property int animFast:   120
    readonly property int animNormal: 200
    readonly property int animSlow:   350

    // Opacity levels
    readonly property real opacityHover:    0.08
    readonly property real opacityPress:    0.12
    readonly property real opacityDisabled: 0.38
    readonly property real opacityOverlay:  0.72

    // Icon sizes
    readonly property int iconSm: 16
    readonly property int iconMd: 18
    readonly property int iconLg: 22
    readonly property int iconXl: 28
}
