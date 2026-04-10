# MouseTrail Modernization TODOs (2025)

## ✅ Recent Improvements Completed
- [x] Switched to one-shot screen capture - Better performance than continuous streaming
- [x] Added comprehensive debug logging - DebugLogger class with timestamped messages  
- [x] Implemented edge-aware ripple sizing - Smart adjustment near screen edges
- [x] Enhanced ripple effects - Multi-wave distortions with better blending
- [x] Improved coordinate system handling - Robust bottom-left to top-left conversions
- [x] Removed menu bar - Simplified the app structure

## 🔄 Modernization Tasks

### 1. Swift 6.2 Concurrency Migration
- [ ] Replace remaining `DispatchQueue.main.async` with `@MainActor` annotations
- [ ] Convert `Task { }` to structured concurrency with proper actor isolation
- [ ] Update RippleManager to be an `actor` for thread safety
- [ ] Replace `Timer` with Swift's `AsyncStream` for animation updates
- [ ] Use `withTaskCancellationHandler` for proper cleanup

### 2. macOS 15 Sequoia Window Features
- [ ] Add `cascadingReferenceFrame` support for Window Tiling compatibility
- [ ] Implement proper `resizeIncrements` for the info panel
- [ ] Update window styling to support new Liquid Glass materials
- [ ] Test with Stage Manager enabled

### 3. SwiftUI Integration Points
- [ ] Replace NSSlider controls with SwiftUI views via NSHostingView
- [ ] Use SwiftUI Animation types with NSAnimationContext
- [ ] Consider NSHostingMenu for any future menu needs
- [ ] Create SwiftUI-based preferences window

### 4. ScreenCaptureKit Optimizations
- [ ] Add proper async error handling with typed errors
- [ ] Implement SCStreamDelegate for better capture state management
- [ ] Add HDR content support detection
- [ ] Optimize capture performance for high refresh rate displays

### 5. Performance Improvements
- [ ] Replace Timer with CADisplayLink for true vsync sync
- [ ] Use `@unchecked Sendable` for performance-critical TrailPoint struct
- [ ] Implement view recycling for ripple effects
- [ ] Add Metal rendering for trail if performance becomes an issue
- [ ] Profile and optimize memory usage

### 6. Modern AppKit Patterns
- [ ] Use `NSAppearance.performAsCurrentDrawingAppearance` for dark mode support
- [ ] Implement `NSWindowDelegate` methods for better window lifecycle
- [ ] Add support for Stage Manager with proper `collectionBehavior`
- [ ] Use `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` for accessibility

### 7. Code Organization
- [ ] Split into multiple files:
  - [ ] `TrailView.swift`
  - [ ] `RippleEffect.swift` & `RippleManager.swift`
  - [ ] `DebugLogger.swift`
  - [ ] `SelectiveClickPanel.swift`
  - [ ] `Extensions.swift` for NSColor, CGRect helpers
- [ ] Add proper access control (`private`, `internal`, `public`)
- [ ] Use Swift Package Manager structure
- [ ] Add documentation comments

### 8. New Features to Add
- [ ] **Menu Bar Toggle**: Re-add as optional with NSStatusItem
- [ ] **Keyboard Shortcuts**: Global hotkeys for enable/disable
- [ ] **Preferences Window**: SwiftUI-based settings
- [ ] **Export/Import Settings**: JSON configuration
- [ ] **Multi-touch Support**: Track multiple pointers
- [ ] **Recording Mode**: Save trail animations as video
- [ ] **Custom Trail Shapes**: Beyond just circles
- [ ] **Trail Presets**: Save/load trail configurations

### 9. Testing & Documentation
- [ ] Add XCTest unit tests for coordinate conversions
- [ ] UI tests for panel interactions
- [ ] DocC documentation for public APIs
- [ ] Performance tests for trail rendering
- [ ] Create user documentation/README

### 10. API Updates
- [ ] Replace any deprecated APIs
- [ ] Add `@available` annotations for newer APIs
- [ ] Ensure minimum deployment target of macOS 14.0
- [ ] Update Info.plist with proper permissions descriptions

## Priority Order
1. **High Priority**: Swift 6.2 concurrency, Code organization
2. **Medium Priority**: SwiftUI integration, Performance improvements
3. **Low Priority**: New features, Additional testing

## Notes
- The app already uses modern ScreenCaptureKit APIs effectively
- Current architecture is solid but could benefit from modularization
- Performance is good but can be optimized further with modern APIs
- Consider creating a GitHub repo for version control