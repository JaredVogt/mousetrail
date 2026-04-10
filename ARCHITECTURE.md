# MouseTrail Architecture

This document provides a detailed technical overview of the MouseTrail, explaining its architecture, design patterns, and implementation details. This app serves as an example of modern macOS development using Swift and Cocoa.

## Table of Contents
1. [Overview](#overview)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Technical Concepts](#technical-concepts)
5. [Code Walkthrough](#code-walkthrough)
6. [Event Flow](#event-flow)
7. [Extension Ideas](#extension-ideas)

## Overview

MouseTrail is a single-file Swift application that demonstrates several advanced macOS programming concepts:
- Custom window management with selective mouse interaction
- Global event monitoring without requiring special permissions
- Real-time animation using timers
- Multi-window coordination
- Background application behavior

The app runs as a UI element (LSUIElement), meaning it doesn't appear in the Dock and is designed to be an overlay tool.

## Project Structure

```
MouseTrail/
├── main.swift              # Single source file containing all code
├── build-working.sh        # Build script for creating .app bundle
├── README.md              # User documentation
├── ARCHITECTURE.md        # This file
└── MouseTrail.app/   # Generated application bundle
    └── Contents/
        ├── Info.plist     # Application metadata
        └── MacOS/
            └── MouseTrail  # Compiled executable
```

### Why Single File?

This example uses a single-file architecture to:
- Simplify understanding of component relationships
- Make it easy to see all code at once
- Reduce complexity for learning purposes
- Enable quick compilation without build systems

## Core Components

### 1. SelectiveClickPanel (Custom NSPanel)

```swift
class SelectiveClickPanel: NSPanel
```

A specialized window that implements selective mouse interaction:

**Key Features:**
- Inherits from `NSPanel` for floating window behavior
- Starts with `ignoresMouseEvents = true` for click-through behavior
- Uses `NSTrackingArea` to detect mouse hover over close button
- Dynamically enables mouse events only when needed

**Design Pattern:** 
This implements the "Smart Window" pattern where the window intelligently manages its own interaction state based on user intent.

### 2. AppDelegate (Application Controller)

```swift
class AppDelegate: NSObject, NSApplicationDelegate
```

The main application controller that manages:
- Window lifecycle
- Event monitoring
- Timer-based updates
- Resource cleanup

**Responsibilities:**
- Creates and configures both windows (info panel and red ball)
- Sets up global event monitors for mouse movement and keyboard modifiers
- Manages the animation loop via Timer
- Handles application termination cleanup

### 3. Window Management System

The app creates two independent windows:

1. **Info Panel Window** (`SelectiveClickPanel`)
   - Displays system information
   - Has selective mouse interaction
   - Can be dragged with Command key

2. **Ball Window** (`NSPanel`)
   - Simple overlay for the red ball
   - Always ignores mouse events
   - Follows mouse with trailing effect

## Technical Concepts

### 1. Event Monitoring

The app uses three types of event monitors:

```swift
// Global mouse movement monitoring
NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)

// Global keyboard modifier monitoring
NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)

// Local keyboard modifier monitoring (when app has focus)
NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)
```

**Why both global and local?**
- Global monitors catch events when the app isn't focused
- Local monitors ensure events are caught when the app is active
- This dual approach ensures reliable modifier key detection

### 2. Trailing Animation Algorithm

The red ball trailing effect uses a position history buffer:

```swift
var mousePositionHistory: [NSPoint] = []
```

**How it works:**
1. Initialize buffer with current position (repeated `ballTrailDelay` times)
2. On each update, append new position to end
3. Remove oldest position if buffer exceeds size
4. Use the oldest position for ball placement

This creates a smooth, delayed following effect.

### 3. Window Layering

Window levels ensure proper stacking:

```swift
window.level = .floating        // Info panel floats above normal windows
ballWindow.level = .floating    // Ball also floats
```

Collection behaviors ensure windows appear on all spaces:

```swift
window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary, .fullScreenAuxiliary]
```

### 4. Selective Mouse Interaction

The `SelectiveClickPanel` uses `NSTrackingArea` to monitor mouse location:

```swift
NSTrackingArea(
    rect: button.frame,
    options: [.mouseEnteredAndExited, .activeAlways],
    owner: self,
    userInfo: nil
)
```

When mouse enters the close button area:
1. `mouseEntered()` is called
2. `ignoresMouseEvents` is set to `false`
3. Button becomes clickable

When mouse exits:
1. `mouseExited()` is called
2. `ignoresMouseEvents` returns to `true` (unless dragging)

### 5. Background App Configuration

The app runs without a Dock icon:

```swift
app.setActivationPolicy(.prohibited)
```

Combined with `LSUIElement` in Info.plist, this creates a true background utility.

## Code Walkthrough

### Initialization Flow

1. **Bootstrap** (main.swift:346-350)
   - Create NSApplication instance
   - Create and assign AppDelegate
   - Set activation policy
   - Start run loop

2. **App Launch** (`applicationDidFinishLaunching`)
   - Verify screens available
   - Create info window at mouse position
   - Configure window properties
   - Create UI elements (border, label, close button)
   - Set up tracking area
   - Create ball window
   - Start event monitors and timer

3. **Window Creation**
   - Info window: Custom panel with specific behaviors
   - Ball window: Simple panel for animation
   - Both configured for floating and all-spaces behavior

### Update Cycle

The app updates through multiple mechanisms:

1. **Timer-based updates** (60 FPS)
   - Update display information
   - Update ball position for smooth animation

2. **Event-driven updates**
   - Mouse movement updates coordinates immediately
   - App switching triggers info refresh
   - Modifier keys change window behavior

### Cleanup Flow

When terminating (`applicationWillTerminate`):
1. Invalidate and nil timer
2. Remove event monitors
3. Close ball window
4. Remove notification observers

This ensures no memory leaks or orphaned resources.

## Event Flow

### Mouse Movement

```
User moves mouse
    ↓
Global mouse event monitor triggered
    ↓
updateDisplay() - Updates coordinate text
    ↓
updateBallPosition() - Adds position to history
    ↓
updateBallWindowPosition() - Moves ball window
```

### Command Key Press

```
User presses Command key
    ↓
flagsChanged event triggered (global + local)
    ↓
handleFlagsChanged() called
    ↓
Window draggable state updated
Border color changes to yellow
Mouse events enabled for entire window
```

### Close Button Interaction

```
Mouse enters close button area
    ↓
NSTrackingArea triggers mouseEntered
    ↓
Window enables mouse events
    ↓
User clicks button
    ↓
closeButtonClicked() called
    ↓
NSApplication.terminate()
```

## Extension Ideas

### 1. Customizable Ball Appearance

Add preferences for:
```swift
// In Constants
static let ballColor: NSColor = .red
static let ballOpacity: CGFloat = 0.8
static let ballShadowEnabled: Bool = true
```

Consider creating a preferences window or reading from UserDefaults.

### 2. Multiple Trailing Objects

Create an array of ball windows:
```swift
var ballWindows: [NSPanel] = []
var ballViews: [NSView] = []

// Create multiple balls with different delays
for i in 0..<5 {
    let delay = Constants.ballTrailDelay * (i + 1)
    // Create ball with increasing delay
}
```

### 3. Custom Info Display

Add more system information:
```swift
// CPU usage
let cpuUsage = // ... get CPU info
displayText += "CPU: \(cpuUsage)%\n"

// Memory usage
let memoryUsage = // ... get memory info
displayText += "Memory: \(memoryUsage)GB\n"

// Network status
let networkStatus = // ... get network info
displayText += "Network: \(networkStatus)\n"
```

### 4. Gesture Support

Add trackpad gestures:
```swift
let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan))
window.contentView?.addGestureRecognizer(panGesture)

@objc func handlePan(_ gesture: NSPanGestureRecognizer) {
    // Handle window movement via gesture
}
```

### 5. Themes

Implement different visual themes:
```swift
enum Theme {
    case dark, light, neon, minimal
    
    var borderColor: NSColor { /* ... */ }
    var backgroundColor: NSColor { /* ... */ }
    var textColor: NSColor { /* ... */ }
}
```

### 6. Recording/Playback

Record mouse movements and replay them:
```swift
struct MouseRecord {
    let timestamp: TimeInterval
    let position: NSPoint
}

var recording: [MouseRecord] = []
var isRecording = false
var isPlaying = false
```

### 7. Hot Corners

Trigger actions when mouse enters screen corners:
```swift
func checkHotCorners(_ location: NSPoint) {
    let threshold: CGFloat = 10
    
    if location.x < threshold && location.y < threshold {
        // Bottom-left corner action
    }
    // Check other corners...
}
```

## Best Practices Demonstrated

1. **Memory Management**
   - Weak self references in closures
   - Proper cleanup in dealloc
   - Timer invalidation

2. **Event Handling**
   - Both global and local monitors
   - Proper event removal
   - Efficient update batching

3. **UI Responsiveness**
   - 60 FPS update rate
   - Minimal work in event handlers
   - Smart window interaction

4. **Code Organization**
   - Clear separation of concerns
   - Constants enumeration
   - Logical method grouping

## Performance Considerations

The app is designed to be lightweight:
- Timer runs at 60 FPS but only updates when needed
- Mouse history buffer has fixed size
- No complex calculations in hot paths
- Minimal memory allocation during runtime

## Security Notes

The app requires no special permissions because:
- It uses public APIs for event monitoring
- No accessibility features are accessed
- No user data is stored or transmitted
- All operations are read-only system queries

This makes it safe to run without privacy concerns.

## Conclusion

MouseTrail demonstrates how to build a modern macOS utility using Swift and Cocoa. It showcases window management, event handling, animation, and system integration in a clean, understandable package. The single-file architecture makes it an excellent learning resource for macOS development.