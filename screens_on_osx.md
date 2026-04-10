# macOS Screen Coordinates: A Comprehensive Guide

This document provides a detailed reference for handling screen coordinates on macOS, covering the various coordinate systems used by different APIs and how to convert between them correctly.

## Table of Contents
1. [Coordinate System Overview](#coordinate-system-overview)
2. [Multi-Display Arrangements](#multi-display-arrangements)
3. [API-Specific Coordinate Systems](#api-specific-coordinate-systems)
4. [Coordinate Conversion Formulas](#coordinate-conversion-formulas)
5. [Known Issues and Workarounds](#known-issues-and-workarounds)
6. [Code Examples](#code-examples)
7. [Testing Strategies](#testing-strategies)

## Coordinate System Overview

macOS uses multiple coordinate systems depending on the API and context:

### Bottom-Left Origin (Traditional macOS)
- **Origin**: (0, 0) at bottom-left corner
- **Y-axis**: Increases upward
- **Used by**: NSScreen, NSWindow, NSView, NSEvent

### Top-Left Origin (Modern APIs)
- **Origin**: (0, 0) at top-left corner
- **Y-axis**: Increases downward
- **Used by**: ScreenCaptureKit, Core Graphics contexts (sometimes)

### Key Principle
The fundamental challenge in macOS coordinate handling is converting between these two systems while accounting for multi-display arrangements.

## Multi-Display Arrangements

### Virtual Desktop Space
All displays exist in a single virtual coordinate space:
- The primary display typically starts at (0, 0)
- Secondary displays can be positioned anywhere relative to the primary
- Displays can have X and Y offsets

### Display Properties
```swift
// NSScreen properties
screen.frame         // Global position and size in virtual desktop
screen.visibleFrame  // Excludes menu bar and dock
screen.frame.origin  // Can have non-zero X and Y values
```

### Common Arrangements
1. **Side-by-side**: Secondary display to the right (positive X offset)
2. **Stacked**: Secondary display above/below (Y offset)
3. **Diagonal**: Both X and Y offsets
4. **Not aligned**: Displays not edge-aligned (common with different resolutions)

## API-Specific Coordinate Systems

### NSScreen (AppKit)
- **Coordinate System**: Bottom-left origin
- **Global Coordinates**: All screens share a virtual desktop space
- **Main Screen**: Not always at (0, 0) - check `screen.frame.origin`

```swift
// Get all displays
let screens = NSScreen.screens

// Each screen has:
// - frame: CGRect in global coordinates
// - frame.origin: Can be non-zero!
// - frame.size: Display resolution
```

### NSEvent (Mouse Events)
- **Coordinate System**: Bottom-left origin
- **Always Global**: Mouse locations are in virtual desktop coordinates

```swift
// Mouse location is always global
let mouseLocation = NSEvent.mouseLocation
// This is in bottom-left coordinates relative to virtual desktop
```

### ScreenCaptureKit
- **Coordinate System**: Top-left origin
- **Display-Relative**: Coordinates are relative to each display
- **CRITICAL BUG**: Displays with Y offsets behave differently!

```swift
// SCStreamConfiguration expects:
// - x, y relative to display top-left
// - BUT for displays with Y offset, it may expect global coordinates!
```

### NSWindow
- **Coordinate System**: Bottom-left origin
- **Frame**: In global screen coordinates
- **Content View**: Local to window (0, 0) at bottom-left

### Core Graphics
- **Variable**: Can be either top-left or bottom-left depending on context
- **Bitmap Contexts**: Usually top-left
- **Screen Contexts**: Usually bottom-left

## Coordinate Conversion Formulas

### Basic Conversions

#### Global to Display-Relative (Bottom-Left)
```swift
let displayRelativeX = globalPoint.x - display.frame.origin.x
let displayRelativeY = globalPoint.y - display.frame.origin.y
```

#### Bottom-Left to Top-Left (Within Display)
```swift
// For a point
let topLeftY = display.frame.height - bottomLeftY

// For a rect (need to use top edge)
let topLeftY = display.frame.height - (bottomLeftRect.origin.y + bottomLeftRect.height)
```

### ScreenCaptureKit Special Case

**CRITICAL**: ScreenCaptureKit has inconsistent behavior with Y-offset displays!

```swift
// Standard formula (works for displays at Y=0)
let displayRelativeX = rect.origin.x - display.frame.origin.x
let rectYFromDisplayBottom = rect.origin.y - display.frame.origin.y
let displayRelativeY = display.frame.height - (rectYFromDisplayBottom + rect.height)

// REQUIRED WORKAROUND for displays with Y offset
if display.frame.origin.y > 0 {
    // Use global Y coordinate directly!
    displayRelativeY = display.frame.height - (rect.origin.y + rect.height)
}
```

### Complete Conversion Function
```swift
func convertToScreenCaptureCoordinates(rect: CGRect, display: NSScreen) -> CGRect {
    // X is always display-relative
    let displayRelativeX = rect.origin.x - display.frame.origin.x
    
    // Y requires special handling
    var displayRelativeY: CGFloat
    
    if display.frame.origin.y > 0 {
        // Display has Y offset - use global coordinates
        displayRelativeY = display.frame.height - (rect.origin.y + rect.height)
    } else {
        // Standard display - use relative coordinates
        let rectYFromDisplayBottom = rect.origin.y - display.frame.origin.y
        displayRelativeY = display.frame.height - (rectYFromDisplayBottom + rect.height)
    }
    
    return CGRect(x: displayRelativeX, y: displayRelativeY, 
                  width: rect.width, height: rect.height)
}
```

## Known Issues and Workarounds

### 1. ScreenCaptureKit Y-Offset Bug
**Problem**: Displays with non-zero Y origins don't follow standard coordinate conversion.

**Symptom**: Screen captures are vertically offset on secondary displays positioned above/below the primary.

**Solution**: Use global Y coordinates for offset displays (see formula above).

### 2. Retina Display Scaling
**Problem**: Logical vs physical pixels can cause confusion.

**Solution**: Always work with logical coordinates; the system handles scaling.

```swift
// Get backing scale factor if needed
let scaleFactor = screen.backingScaleFactor
```

### 3. Display Arrangement Changes
**Problem**: Displays can be rearranged while app is running.

**Solution**: Listen for display notifications:
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(screensDidChange),
    name: NSApplication.didChangeScreenParametersNotification,
    object: nil
)
```

## Code Examples

### Finding Which Display Contains a Point
```swift
func findDisplay(for point: NSPoint) -> NSScreen? {
    return NSScreen.screens.first { screen in
        screen.frame.contains(point)
    }
}
```

### Capturing Screen Area (with Workaround)
```swift
func captureScreenArea(rect: CGRect) async throws -> CGImage? {
    let content = try await SCShareableContent.excludingDesktopWindows(false, 
                                                                       onScreenWindowsOnly: true)
    
    guard let display = content.displays.first(where: { $0.frame.contains(rect) }) else {
        return nil
    }
    
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    
    // Convert coordinates with special handling
    let captureRect = convertToScreenCaptureCoordinates(rect: rect, display: display)
    
    config.sourceRect = captureRect
    config.width = Int(captureRect.width)
    config.height = Int(captureRect.height)
    
    return try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: config
    )
}
```

### Debug Logging for Coordinate Issues
```swift
func logCoordinateConversion(clickPoint: NSPoint, display: NSScreen) {
    print("=== COORDINATE DEBUG ===")
    print("Click point (global): \(clickPoint)")
    print("Display frame: \(display.frame)")
    print("Display Y offset: \(display.frame.origin.y)")
    print("Is primary display: \(display.frame.origin == .zero)")
    
    let displayRelative = NSPoint(
        x: clickPoint.x - display.frame.origin.x,
        y: clickPoint.y - display.frame.origin.y
    )
    print("Display-relative (bottom-left): \(displayRelative)")
    
    let topLeftY = display.frame.height - displayRelative.y
    print("Display-relative (top-left): (\(displayRelative.x), \(topLeftY))")
}
```

## Testing Strategies

### 1. Test Multiple Display Arrangements
- Single display
- Side-by-side displays
- Vertically stacked displays
- Displays with gaps (not edge-aligned)
- Three or more displays

### 2. Test Edge Cases
- Click at display boundaries
- Capture across display boundaries
- Primary display not at (0, 0)
- Different resolution displays

### 3. Automated Testing
```swift
func testCoordinateConversion() {
    // Test cases for known problematic arrangements
    let testCases = [
        // Display at origin
        (display: CGRect(x: 0, y: 0, width: 1920, height: 1080),
         point: CGPoint(x: 960, y: 540),
         expected: CGPoint(x: 960, y: 540)),
        
        // Display with Y offset
        (display: CGRect(x: 1920, y: 100, width: 1920, height: 1080),
         point: CGPoint(x: 2880, y: 640),
         expected: CGPoint(x: 960, y: 540))
    ]
    
    for testCase in testCases {
        // Run conversion and verify
    }
}
```

### 4. Visual Debugging
Add visual indicators to confirm correct positioning:
- Draw borders around capture areas
- Show crosshairs at click points
- Log all coordinate transformations

## Summary

When working with macOS screen coordinates:

1. **Always identify** which coordinate system your input and output use
2. **Check display origins** - never assume (0, 0)
3. **Test with multiple displays** in various arrangements
4. **Apply the ScreenCaptureKit workaround** for Y-offset displays
5. **Log extensively** during development
6. **Handle display changes** dynamically

Remember: The ScreenCaptureKit Y-offset bug is a critical issue that requires special handling. Always test with displays that have non-zero Y origins!