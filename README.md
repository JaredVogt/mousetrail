# MouseTrail

A macOS application that displays system information in a floating overlay window and features a red ball that follows your mouse cursor with a trailing effect.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2010.15%2B-lightgrey.svg)
![Language](https://img.shields.io/badge/language-Swift-orange.svg)

## Features

### 🖱️ Real-time Mouse Tracking
- Displays current mouse coordinates (x, y) in screen space
- Updates in real-time as you move your mouse
- Works across all monitors in multi-display setups

### 🔴 Animated Red Ball Follower
- A small red ball that follows your mouse cursor
- Smooth trailing animation with configurable delay
- Semi-transparent with subtle shadow for depth
- Non-intrusive - doesn't interfere with mouse clicks

### 📊 System Information Display
- Shows the currently active application
- Lists all connected displays with resolutions
- Identifies the main display
- Updates instantly when switching between apps

### 🎯 Smart Window Interaction
- **Floating overlay** that stays above other windows
- **Selective click-through**: Window ignores mouse events except on the close button
- **Draggable mode**: Hold Command (⌘) key to drag the window
  - Border turns yellow when in drag mode
  - Release Command to lock position
- **Close button**: Red × button in the top-right corner

## Installation

### Quick Start
1. Download the latest release or build from source
2. Double-click `MouseTrail.app` to launch
3. The overlay window appears at your current mouse position
4. A red ball starts following your mouse cursor

### Building from Source

#### Prerequisites
- macOS 10.15 (Catalina) or later
- Xcode Command Line Tools installed
- Swift compiler (comes with Xcode)

#### Build Steps
```bash
# Clone the repository
git clone [repository-url]
cd MouseTrail

# Run the build script
./build-working.sh

# Or compile manually
swiftc main.swift -o MouseTrail
```

## Usage

### Launching the App

**Option 1: Double-click the app bundle**
```bash
# After building, double-click MouseTrail.app in Finder
```

**Option 2: Command line**
```bash
# Run the executable directly
./MouseTrail

# Or use the app bundle
./MouseTrail.app/Contents/MacOS/MouseTrail
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| ⌘ (Command) | Hold to enable window dragging |
| ⌘Q | Quit the application |

### Window Interaction

1. **Moving the window**: Hold Command (⌘) and drag
2. **Closing the app**: Click the red × button
3. **Normal operation**: Window is click-through except for the close button

## System Requirements

- **macOS**: 10.15 (Catalina) or later
- **Permissions**: May require accessibility permissions for global mouse tracking
- **Memory**: Minimal (~10MB)
- **Display**: Works with single or multiple monitors

## Troubleshooting

### App doesn't appear when launched
- Check if the app is running: `ps aux | grep MouseTrail`
- The window spawns at your current mouse location - move your mouse and look for it
- The red ball should be visible following your cursor

### Terminal window opens when launching
- This is expected behavior for command-line tools on macOS
- Use the Automator method described in the documentation to avoid this
- Or run with `./MouseTrail & disown` and close Terminal

### Window is not draggable
- Ensure you're holding the Command (⌘) key
- The border should turn yellow when drag mode is active
- Release Command to lock the window position

### Mouse tracking seems delayed
- The red ball intentionally has a trailing delay for visual effect
- The coordinate display updates at 60 FPS for smooth tracking
- Check Activity Monitor if performance seems unusually slow

## Privacy & Security

This app requires no special permissions by default. However:
- It monitors global mouse movements to update the display
- It reads the name of the active application
- No data is stored or transmitted
- All processing happens locally on your machine

## License

This project is released as an example application for educational purposes. Feel free to use, modify, and distribute as needed.

## Contributing

This is an example project designed to demonstrate macOS development concepts. Feel free to fork and experiment!

## Acknowledgments

Built with Swift and the Cocoa framework, demonstrating:
- Custom NSPanel implementation
- Global event monitoring
- Real-time UI updates
- Overlay window management