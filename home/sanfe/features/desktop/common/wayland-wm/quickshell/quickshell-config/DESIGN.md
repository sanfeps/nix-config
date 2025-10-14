# QuickShell Design Document

## Design Philosophy

This QuickShell configuration follows a **minimalist aesthetic** with:

- **Clean lines** and subtle rounded corners
- **Muted color palette** based on Catppuccin Mocha
- **Smooth animations** for a polished feel
- **Functional design** - every element serves a purpose
- **Visual hierarchy** using spacing, color, and typography

## Color Palette

### Primary Colors
```
Background:   #1e1e2e  (bg)
Surface:      #45475a  (surface)
Accent:       #89b4fa  (blue)
Text:         #cdd6f4  (white)
```

### Semantic Colors
```
Success:      #a6e3a1  (green)  - Battery healthy, network connected
Warning:      #f9e2af  (yellow) - Battery medium
Error:        #f38ba8  (red)    - Battery low, critical notifications
Special:      #cba6f7  (purple) - Special highlights
```

### Usage Examples
- **Active workspace**: Filled with accent color (#89b4fa)
- **Inactive workspace with windows**: Outlined with overlay color
- **Empty workspace**: Transparent, minimal presence
- **Low battery**: Text turns red (#f38ba8)
- **Charging**: Lightning bolt in accent blue (#89b4fa)

## Layout Structure

### Status Bar (32px height)
```
┌─────────────────────────────────────────────────────────────────┐
│  [1][2][3]    Active Window Title         [Net][Vol][Bat][Time] │
└─────────────────────────────────────────────────────────────────┘
```

**Left Section**: Workspace indicators (1, 2, 3, etc.)
**Center Section**: Active window title (centered, elided if too long)
**Right Section**: System tray (Network, Volume, Battery, Clock)

### App Launcher (600x400px)
```
┌─────────────────────────────────────────┐
│  [Search icon] Search applications...   │
├─────────────────────────────────────────┤
│  [icon] Firefox                    [x]  │
│         Web Browser                     │
├─────────────────────────────────────────┤
│  [icon] Terminal                   [x]  │
│         Terminal Emulator               │
└─────────────────────────────────────────┘
```

Centered on screen, appears on demand

### Notifications (400px width)
```
                              ┌─────────────────────────┐
                              │ [!] Title          [x] │
                              │     Notification body   │
                              │     text here...        │
                              │                 10:30   │
                              └─────────────────────────┘
```

Appears in top-right corner, below the status bar

## Component Details

### Workspaces Widget
- **Size**: 20x20px per workspace
- **Spacing**: 8px between workspaces
- **Active**: Solid accent color fill, white number
- **Has Windows**: Surface color fill or outlined
- **Empty**: Transparent with border
- **Interaction**: Click to switch, hover opacity change

### Clock Widget
- **Two sections**: Time (HH:MM) and Date (MMM DD)
- **Background**: Alternate background color (#313244)
- **Padding**: 8px horizontal
- **Font**: Time is medium weight, date is regular

### Battery Widget
- **Dynamic icon**: Changes based on percentage (10%, 30%, 50%, 70%, 90%)
- **Color coding**:
  - Green (>50%): Healthy
  - Yellow (20-50%): Warning
  - Red (<20%): Critical
- **Charging indicator**: Lightning bolt icon when charging

### Volume Widget
- **Dynamic icon**: Muted, low, medium, high
- **Interactive**:
  - Click to mute/unmute
  - Scroll to adjust volume
- **Muted state**: Red color

### Window Title
- **Max width**: Fills available center space
- **Overflow**: Ellipsis at end
- **Visibility**: Only shown when window is focused

## Animations

All animations use **150ms duration** for snappiness:

- **Color transitions**: Smooth ColorAnimation
- **Hover states**: Opacity changes (0.8 on hover)
- **Notification entrance**: Slide-in from right + fade in (parallel)
- **Workspace switching**: Color transition

Slower animations (300ms) for:
- Complex transitions
- Multi-step animations

## Typography

### Font Sizes
```
Small:   10px  - Secondary info (date, battery %)
Normal:  12px  - Primary text (workspace numbers, titles)
Large:   14px  - Emphasized text
XL:      16px  - Icons, app names
Title:   20px  - Large headings
```

### Font Weights
- **Regular**: Default text
- **Medium**: Important text (time, active workspace)
- **Bold**: Headings, notification titles

## Spacing System

### Padding
```
Small:  4px
Normal: 8px   (default)
Large:  12px
XL:     16px
```

### Border Radius
```
Small:  4px   (workspace indicators)
Normal: 8px   (default for widgets)
Large:  12px  (launcher, large panels)
```

## Interactive States

### Hover
- Cursor changes to pointing hand
- Slight opacity reduction (0.8)
- Color transition on buttons

### Active
- Distinct color (accent for workspaces)
- Bold or medium font weight
- Higher contrast

### Disabled
- Reduced opacity (0.4)
- No cursor change
- Muted colors

## Accessibility

- **Minimum contrast**: 4.5:1 for normal text
- **Touch targets**: Minimum 24x24px for clickable elements
- **Keyboard navigation**: Full support in launcher
- **Visual feedback**: Clear hover and active states

## Future Enhancements

### Planned Features
1. **Media controls** - Play/pause, track info
2. **Calendar popup** - Click on date to show calendar
3. **System tray icons** - Support for legacy tray icons
4. **Workspace names** - Custom names instead of numbers
5. **Weather widget** - Temperature and conditions
6. **Quick settings** - Brightness, night light, DND

### Design Considerations
- Maintain minimalist aesthetic
- Keep bar height under 40px
- Use consistent spacing and colors
- Smooth, purposeful animations
- Contextual information (show only when needed)

## Inspiration

This design draws inspiration from:

1. **Catppuccin Mocha** - Color palette
2. **Material Design** - Spacing and elevation principles
3. **macOS** - Clean, functional design
4. **caelestia-shell** - Widget organization
5. **AGS configurations** - Modern wayland shell patterns
