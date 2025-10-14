# QuickShell Configuration

A beautiful, minimalist desktop shell configuration for Hyprland using QuickShell.

## Features

### Status Bar
- **Workspaces**: Visual workspace indicators with active/inactive states
- **Window Title**: Centered display of the active window title
- **System Tray**:
  - Clock with time and date
  - Battery indicator with percentage and charging status
  - Volume control with click-to-mute and scroll-to-adjust
  - Network status indicator

### App Launcher
- Clean, searchable application launcher
- Keyboard navigation support (Up/Down arrows, Enter to launch, Esc to close)
- Mouse click support
- Smooth animations

### Notifications
- Elegant notification system with automatic dismissal
- Support for different urgency levels (normal/critical)
- Manual dismiss option
- Slide-in animations

## Structure

```
quickshell-config/
├── shell.qml              # Main entry point
├── Theme.qml              # Color scheme and design tokens
├── qmldir                 # QML module definition
├── modules/
│   ├── bar/
│   │   └── Bar.qml       # Status bar component
│   ├── launcher/
│   │   └── Launcher.qml  # App launcher component
│   ├── notifications/
│   │   └── Notifications.qml  # Notification system
│   └── widgets/
│       ├── Workspaces.qml     # Workspace indicator
│       ├── WindowTitle.qml    # Window title display
│       ├── Clock.qml          # Clock widget
│       ├── Battery.qml        # Battery widget
│       ├── Volume.qml         # Volume widget
│       └── Network.qml        # Network widget
└── README.md
```

## Theme

The configuration uses a dark minimalist theme inspired by Catppuccin Mocha. All colors, spacing, and sizing are defined in `Theme.qml` for easy customization.

### Customizing Colors

Edit `Theme.qml` to change the color scheme:

```qml
// Primary colors
readonly property color bg: "#1e1e2e"           // Main background
readonly property color accent: "#89b4fa"       // Accent color
readonly property color text: "#cdd6f4"         // Text color
```

### Customizing Spacing

Adjust spacing and sizing in `Theme.qml`:

```qml
readonly property int barHeight: 32             // Height of the status bar
readonly property int padding: 8                // Default padding
readonly property int radius: 8                 // Border radius
```

## Widgets

### Volume Widget
- **Click**: Toggle mute
- **Scroll**: Adjust volume up/down

### Workspace Widget
- **Click**: Switch to workspace
- Visual indicators for active/occupied workspaces

### Battery Widget
- Color-coded based on charge level
- Shows charging indicator
- Icons change based on battery percentage

## Integration

### Hyprland Configuration

To enable the launcher with a keybind, you'll need to set up IPC communication. For now, QuickShell loads automatically when started.

Start QuickShell:
```bash
quickshell -c ~/.config/quickshell/quickshell-config
```

### Auto-start

Add to your Hyprland config:
```
exec-once = quickshell -c ~/.config/quickshell/quickshell-config
```

## Customization

### Adding New Widgets

1. Create a new widget file in `modules/widgets/`
2. Import it in the Bar.qml
3. Add it to the appropriate section (left/center/right)

Example:
```qml
import "../widgets" as Widgets

Widgets.YourNewWidget {
    Layout.alignment: Qt.AlignVCenter
}
```

### Modifying the App Launcher

Edit the `appsModel` in `modules/launcher/Launcher.qml` to customize available applications. In the future, this could be enhanced to scan `.desktop` files automatically.

## Future Enhancements

- Desktop file scanning for app launcher
- Network Manager integration for better network status
- System tray icon support
- Media player controls
- Calendar widget
- Weather widget
- Better keybind integration with Hyprland

## Credits

Inspired by:
- [caelestia-shell](https://github.com/caelestia-dots/shell) by soramanew
- [rivendell-hyprdots](https://codeberg.org/zacoons/rivendell-hyprdots)
- [QuickShell](https://quickshell.org) framework

## License

This configuration is part of a personal NixOS configuration. Feel free to use and modify as needed.
