# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a single-file macOS application written in Swift that creates an overlay displaying mouse coordinates, system information, and features a hardware-accelerated glowing trail that follows the mouse cursor with smooth Catmull-Rom spline interpolation.

## Build Commands

```bash
# Primary build command - creates .app bundle
./build-working.sh

# Manual compilation (without app bundle)
swiftc main.swift -o MouseTrail

# Run the application
./MouseTrail.app/Contents/MacOS/MouseTrail

# Run in background (Terminal closes automatically)
./MouseTrail & disown
```

## Architecture

The application consists of a single `main.swift` file with three main classes:

1. **TrailView**: A hardware-accelerated view that renders a smooth, glowing mouse trail using CAShapeLayer and Catmull-Rom spline interpolation. Features multi-layer glow effects and time-based fading.

2. **SelectiveClickPanel**: A custom NSPanel that implements selective mouse interaction using NSTrackingArea. It ignores mouse events except when hovering over the close button or when Command key is held for dragging.

3. **AppDelegate**: Manages the info panel window and multiple trail windows (one per screen), global event monitoring for mouse/keyboard events, and a 60 FPS timer for smooth animations.

Key architectural decisions:
- Single-file architecture for simplicity
- Runs as LSUIElement (no Dock icon)
- Uses global event monitors that don't require special permissions
- Hardware-accelerated trail rendering with Core Animation
- Separate trail windows for each screen for optimal multi-monitor support
- Windows configured with `.floating` level and `.canJoinAllSpaces` behavior

## Important Implementation Details

### Window Behavior
- Info panel starts at current mouse position
- Windows are click-through except for close button
- Hold Command (⌘) to enable dragging (border turns yellow)
- All windows appear on all spaces and over full-screen apps
- Trail windows automatically created for each connected display

### Trail Animation System
- Smooth, glowing trail using Catmull-Rom spline interpolation
- Triple-layer rendering: outer glow, middle glow, and bright core
- Time-based fading with configurable fade duration (0.6s default)
- Hardware acceleration via CAShapeLayer for optimal performance
- Updates at 60 FPS via Timer for smooth movement
- Separate trail window per screen for seamless multi-monitor support
- Automatic recreation of trail windows when monitor configuration changes

### Event Monitoring
- Uses both global and local event monitors for reliability
- Global monitors: mouse movement and keyboard modifiers
- Local monitor: keyboard modifiers when app has focus
- Workspace notifications for app switching detection

## Testing Considerations

When testing changes:
1. Verify info panel and trail windows appear correctly
2. Test Command-drag functionality
3. Ensure trail renders smoothly with glow effect
4. Check that close button remains clickable
5. Verify app runs without Dock icon
6. Test trail continuity across multiple displays
7. Verify trail appears on all connected monitors

## Known Behaviors

- Terminal window opens when double-clicking .app (expected for CLI tools)
- App requires no special permissions (uses public APIs only)
- Memory usage should remain constant (~15-20MB)
- CPU usage minimal due to efficient Core Animation rendering
- Trail automatically scales to any number of connected displays
- Dynamic monitor detection - no restart required when connecting/disconnecting displays