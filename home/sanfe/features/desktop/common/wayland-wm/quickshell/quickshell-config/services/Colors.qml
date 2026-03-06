pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Material You palette — updated live when matugen generates colors.json
    property color primary:                  "#cba6f7"
    property color onPrimary:                "#11111b"
    property color primaryContainer:         "#585b70"
    property color onPrimaryContainer:       "#cdd6f4"
    property color secondary:                "#89b4fa"
    property color onSecondary:              "#1e1e2e"
    property color secondaryContainer:       "#313244"
    property color onSecondaryContainer:     "#cdd6f4"
    property color tertiary:                 "#94e2d5"
    property color onTertiary:               "#1e1e2e"
    property color tertiaryContainer:        "#45475a"
    property color onTertiaryContainer:      "#cdd6f4"
    property color error:                    "#f38ba8"
    property color onError:                  "#11111b"
    property color errorContainer:           "#45475a"
    property color onErrorContainer:         "#f38ba8"
    property color background:               "#1e1e2e"
    property color onBackground:             "#cdd6f4"
    property color surface:                  "#181825"
    property color onSurface:                "#cdd6f4"
    property color surfaceVariant:           "#313244"
    property color onSurfaceVariant:         "#bac2de"
    property color outline:                  "#585b70"
    property color outlineVariant:           "#45475a"
    property color shadow:                   "#11111b"
    property color scrim:                    "#11111b"
    property color inverseSurface:           "#cdd6f4"
    property color inverseOnSurface:         "#1e1e2e"
    property color inversePrimary:           "#7c3aed"
    property color surfaceDim:               "#11111b"
    property color surfaceBright:            "#313244"
    property color surfaceContainerLowest:   "#0d0d1a"
    property color surfaceContainerLow:      "#1e1e2e"
    property color surfaceContainer:         "#24273a"
    property color surfaceContainerHigh:     "#313244"
    property color surfaceContainerHighest:  "#45475a"

    property FileView _colorsFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"
        watchChanges: true
        onTextChanged: root._applyColors(text)
        Component.onCompleted: root._applyColors(text)
    }

    function _applyColors(text: string) {
        if (!text || text.trim() === "") return
        try {
            var d = JSON.parse(text)
            if (d.primary)                  root.primary                 = d.primary
            if (d.on_primary)               root.onPrimary               = d.on_primary
            if (d.primary_container)        root.primaryContainer        = d.primary_container
            if (d.on_primary_container)     root.onPrimaryContainer      = d.on_primary_container
            if (d.secondary)                root.secondary               = d.secondary
            if (d.on_secondary)             root.onSecondary             = d.on_secondary
            if (d.secondary_container)      root.secondaryContainer      = d.secondary_container
            if (d.on_secondary_container)   root.onSecondaryContainer    = d.on_secondary_container
            if (d.tertiary)                 root.tertiary                = d.tertiary
            if (d.on_tertiary)              root.onTertiary              = d.on_tertiary
            if (d.tertiary_container)       root.tertiaryContainer       = d.tertiary_container
            if (d.on_tertiary_container)    root.onTertiaryContainer     = d.on_tertiary_container
            if (d.error)                    root.error                   = d.error
            if (d.on_error)                 root.onError                 = d.on_error
            if (d.error_container)          root.errorContainer          = d.error_container
            if (d.on_error_container)       root.onErrorContainer        = d.on_error_container
            if (d.background)               root.background              = d.background
            if (d.on_background)            root.onBackground            = d.on_background
            if (d.surface)                  root.surface                 = d.surface
            if (d.on_surface)               root.onSurface               = d.on_surface
            if (d.surface_variant)          root.surfaceVariant          = d.surface_variant
            if (d.on_surface_variant)       root.onSurfaceVariant        = d.on_surface_variant
            if (d.outline)                  root.outline                 = d.outline
            if (d.outline_variant)          root.outlineVariant          = d.outline_variant
            if (d.shadow)                   root.shadow                  = d.shadow
            if (d.scrim)                    root.scrim                   = d.scrim
            if (d.inverse_surface)          root.inverseSurface          = d.inverse_surface
            if (d.inverse_on_surface)       root.inverseOnSurface        = d.inverse_on_surface
            if (d.inverse_primary)          root.inversePrimary          = d.inverse_primary
            if (d.surface_dim)              root.surfaceDim              = d.surface_dim
            if (d.surface_bright)           root.surfaceBright           = d.surface_bright
            if (d.surface_container_lowest) root.surfaceContainerLowest  = d.surface_container_lowest
            if (d.surface_container_low)    root.surfaceContainerLow     = d.surface_container_low
            if (d.surface_container)        root.surfaceContainer        = d.surface_container
            if (d.surface_container_high)   root.surfaceContainerHigh    = d.surface_container_high
            if (d.surface_container_highest)root.surfaceContainerHighest = d.surface_container_highest
        } catch (e) {
            console.warn("Colors: failed to parse colors.json:", e)
        }
    }
}
