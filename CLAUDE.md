# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

MouseTrail is a macOS menu bar overlay application (SwiftUI `MenuBarExtra` + AppKit) that renders:
- A hardware-accelerated glowing cursor trail (Catmull-Rom spline + multi-layer CAShapeLayer glow)
- Optional ripple effects on click (Core Image + Metal kernel `RippleKernel.ci.metal`)
- A configurable crosshair
- Gesture detection (shake, circle, hyper+circle) that can trigger key presses, shell commands, or visual toggles
- A live info panel showing cursor coordinates and active display

The app runs as `LSUIElement` with a menu bar icon; no Dock icon. Trail windows are created per-`NSScreen` so the effect spans every connected display.

## Build Commands

```bash
# Primary build — compiles Metal kernel, builds bundle, codesigns, installs to /Applications, relaunches.
./build-working.sh
```

**Important:** per user memory, always kill the running MouseTrail and relaunch after building. `build-working.sh` does this automatically (`pkill -x MouseTrail` → `open /Applications/MouseTrail.app`).

## File Layout

13 Swift files (~6,400 lines total):

- `MouseTrailApp.swift` — `@main` SwiftUI entry, wires menu bar + AppDelegate
- `AppCore.swift` — **largest file**; contains `AppDelegate`, `TrailView` (CAShapeLayer trail renderer), `RippleEffect`, `RippleManager`, `LogFileViewer`, global event monitors, animation driver (CADisplayLink + Timer fallback)
- `TrailSettings.swift` — `@Observable` settings model, UserDefaults persistence
- `MenuBarSettingsView.swift` — SwiftUI settings panel (monolithic — refactor candidate)
- `HelpView.swift` — Help window with README viewer (WKWebView)
- `PresetManager.swift` + `TrailPreset.swift` — Codable preset persistence in `~/Library/Application Support/MouseTrail/`
- `LiveInfoModel.swift` — Live system info (cursor position, active display)
- `LaunchAtLoginService.swift` — ServiceManagement wrapper
- Gesture subsystem: `ShakeDetector.swift`, `CircleGestureDetector.swift`, `GestureCalibrator.swift`, `GestureRouter.swift`

Non-Swift:
- `Info.plist`, `entitlements.plist`
- `RippleKernel.ci.metal` — Core Image kernel for ripple distortion
- `README.md`, `ARCHITECTURE.md`, `todos.md`, `znote.md`

## Architecture Notes

### Animation pipeline
- `TrailView` renders trail segments using `CAShapeLayer` with multi-layer glow (outer / middle / inner × core + glow stack).
- `AppDelegate` runs either a `CADisplayLink` (macOS 14+, vsync-synchronized via `displayWindow.displayLink(...)`) or a 60 Hz `Timer` fallback.
- Per-screen trail windows are re-computed on `NSApplication.didChangeScreenParametersNotification`.

### Event monitoring
- `NSEvent.addGlobalMonitorForEvents` only — local monitors intentionally omitted since the app has no key window in normal use and local monitors would double-feed gesture detectors.
- Events monitored: `.mouseMoved`, `.leftMouseDragged`, `.leftMouseDown`, `.leftMouseUp`, `.flagsChanged`.

### Gesture system
- `MouseSample` (`AppCore.swift`) is fed to both `ShakeDetector` and `CircleGestureDetector` on every mouse event.
- Detectors are `struct`s with `mutating func addSample(...) -> Event?`; they own a pruned sample buffer and their own cooldown.
- Detected events route through `GestureRouter` to produce a `GestureAction` (none / toggleVisuals / simulateKeyPress / runShellCommand).
- `hyper+circle` is a special case: when circle fires while hyperkeys are held, the event is queued until hyper release.

### Logging
- `logInfo(...)` / `logDebug(...)` in `AppCore.swift` with `@autoclosure` strings so interpolated messages are skipped when the level is gated out.
- Log level configurable at runtime via settings (`.off / .info / .debug`).
- File-backed via `LogFileViewer`; viewable in-app.

## Permissions Required

The app requires the user to grant these macOS permissions (status shown via banner in the settings panel):

- **Accessibility** — required for `CGEvent`-based hotkey simulation (circle gesture → keystroke)
- **Screen Recording** — required for the ripple effect, which samples screen pixels via `ScreenCaptureKit`

The app does NOT require permissions for basic trail rendering or gesture detection from mouse movement.

## Testing Checklist

When making changes:
1. Trail renders smoothly on primary + secondary monitor
2. Ripple effect triggers on click (with Screen Recording granted)
3. Shake + circle + hyper+circle gestures fire their configured actions
4. Settings panel sliders remain responsive; no UI storms
5. Close buttons still clickable; Command-drag still works
6. Menu bar icon and MenuBarExtra window open without delay
7. App relaunches cleanly after `./build-working.sh`

## Known Refactor Candidates

See `/Users/jaredvogt/.claude/plans/ok-we-are-on-delightful-perlis.md` for a full list. High-priority:
- Split `AppCore.swift` into per-class files (`AppDelegate.swift`, `TrailView.swift`, `Ripple.swift`, `LogFileViewer.swift`) — mechanical, no logic change
- Extract `MenuBarSettingsView` sections into subviews
- Introduce `EventMonitorHub`, `GestureDetector` protocol + ring buffer
- Debounce `TrailSettings.save()` to reduce slider-drag UserDefaults churn
