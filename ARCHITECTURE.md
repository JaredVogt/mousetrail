# MouseTrail Architecture

Technical overview of the MouseTrail app: a macOS menu-bar overlay that renders a glowing cursor trail, click ripples, a crosshair, and gesture-triggered actions.

## Table of Contents
1. [Overview](#overview)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Data Flow](#data-flow)
5. [Event Pipeline](#event-pipeline)
6. [Rendering Pipeline](#rendering-pipeline)
7. [Gesture Pipeline](#gesture-pipeline)
8. [Settings & Persistence](#settings--persistence)
9. [Known Refactor Candidates](#known-refactor-candidates)

## Overview

MouseTrail is a SwiftUI `MenuBarExtra` app with an AppKit-based overlay system. The SwiftUI side owns the menu bar icon, settings panel, and help window; the AppKit side (via `AppDelegate`) owns everything else: overlay windows, event monitors, trail rendering, gestures, ripples.

The app runs as `LSUIElement` — no Dock icon, menu bar only.

## Project Structure

```
MouseTrail/
├── MouseTrailApp.swift         — @main SwiftUI entry, wires MenuBarExtra + AppDelegate
├── AppCore.swift               — AppDelegate, TrailView, RippleEffect, RippleManager, LogFileViewer
├── TrailSettings.swift         — @Observable settings model + UserDefaults persistence
├── MenuBarSettingsView.swift   — SwiftUI settings panel
├── HelpView.swift              — Help window (WKWebView reading README)
├── PresetManager.swift         — Codable preset persistence
├── TrailPreset.swift           — Preset data model
├── LiveInfoModel.swift         — Cursor position / active display observable
├── LaunchAtLoginService.swift  — ServiceManagement wrapper
├── ShakeDetector.swift         — Axis-reversal shake detector
├── CircleGestureDetector.swift — Cumulative-angle circle detector
├── GestureCalibrator.swift     — Live calibration for gesture tuning
├── GestureRouter.swift         — Gesture → action routing
├── RippleKernel.ci.metal       — Core Image kernel for ripple distortion
├── Info.plist, entitlements.plist
└── build-working.sh            — Build script (Metal compile + bundle + sign + install)
```

## Core Components

### AppDelegate (`AppCore.swift`)

The central coordinator. Owns:
- An array of `TrailView` instances, one per `NSScreen`
- `NSPanel` overlay windows (one per screen, `.canJoinAllSpaces`, `.floating`)
- Global `NSEvent` monitors for mouse movement, click, mouseUp, and flag changes
- A `CADisplayLink` (macOS 14+) or `Timer` fallback driving the 60 Hz animation
- `ShakeDetector`, `CircleGestureDetector`, `GestureRouter`, `GestureCalibrator`
- `RippleManager` (click ripples) and the `TrailSettings` reference

### TrailView (`AppCore.swift`)

An `NSView` subclass that renders the trail for one screen. Uses:
- Six `CAShapeLayer`s stacked: outer/middle/inner × core stack + outer/middle/inner × glow stack
- A `CAGradientLayer` mask for smooth fade
- Two additional `CAShapeLayer`s for the crosshair (vertical + horizontal)
- Catmull-Rom spline interpolation through recent trail points
- Time-based point fade computed every frame

### RippleEffect / RippleManager (`AppCore.swift`)

- `RippleEffect` owns a per-click `CALayer` displaying a `CIImage` distorted by the Metal-compiled `RippleKernel.ci.metal` kernel.
- `RippleManager` captures a snapshot of the screen via `ScreenCaptureKit`, spawns a `RippleEffect`, and advances it each frame until its duration elapses.
- Requires Screen Recording permission.

### Settings (`TrailSettings.swift`)

- `@Observable` class holding ~40 properties covering visibility, appearance, gesture parameters, ripple tuning, and performance experiments.
- UserDefaults-backed with debounced persistence (writes coalesce to one per ~300ms of quiet).
- Three callbacks — `onChanged`, `onVisibilityChanged`, `onGestureParamsChanged` — fire immediately on each `didSet` so the UI stays live.

## Data Flow

```
NSEvent (global monitor)
   │
   ▼
AppDelegate.handleMouseMovement(_:)
   │
   ├──► MouseSample → ShakeDetector → ShakeEvent? → GestureRouter → GestureAction
   │
   ├──► MouseSample → CircleGestureDetector → CircleEvent? → GestureRouter → GestureAction
   │
   ├──► MouseSample → rawMouseSamples buffer → emitDelayedTrailPoints
   │                                              │
   │                                              ▼
   │                                           TrailView.addPoint
   │
   └──► GestureCalibrator?.addSample (when calibration panel open)

CADisplayLink tick → AppDelegate.updateActiveAnimation → each TrailView.updateTrail
```

## Event Pipeline

- Global monitors only (`NSEvent.addGlobalMonitorForEvents`). Local monitors are intentionally omitted: the app has no key window in normal use, and having both would double-feed the gesture detectors.
- Events monitored: `.mouseMoved`, `.leftMouseDragged`, `.leftMouseDown`, `.leftMouseUp`, `.flagsChanged`.
- Click-drag classification: `.leftMouseDown` starts a tentative click; if the cursor moves beyond a threshold before `.leftMouseUp`, it's a drag (ripple suppressed).
- `.flagsChanged` detects release of the "hyper" modifier chord, which commits any pending hyper+circle gesture.

## Rendering Pipeline

1. **Sample capture.** Raw mouse samples land in a bounded buffer (`rawMouseSamples`) with timestamps from `ProcessInfo.systemUptime` (monotonic).
2. **Playback delay.** Samples older than `visualPlaybackDelay` are emitted as trail points. This lets us smooth out jittery input by running the renderer slightly behind live input.
3. **Spline fit.** Each frame, `TrailView.updateTrail` rebuilds a `CGPath` via Catmull-Rom interpolation through visible points.
4. **Layer update.** All six trail layers share the same path but different stroke widths, colors, and opacities.
5. **Fade.** Point alpha decays via the gradient mask and timed removal.

A CADisplayLink drives updates on macOS 14+; older systems fall back to a 60 Hz `Timer` with half-frame tolerance so the OS can coalesce wakeups.

## Gesture Pipeline

Each detector is a `struct` with `mutating func addSample(_:) -> Event?`:

- **ShakeDetector** — identifies rapid back-and-forth along a dominant axis. Fires `ShakeEvent(axisAngle, reversals, averageVelocity, angularSpread)`. Angle is normalized to `[0, π)` because shakes are bidirectional.
- **CircleGestureDetector** — tracks cumulative angular displacement around a running-sum centroid. Fires `CircleEvent(direction, averageRadius, circleCount)` when the configured number of circles complete within the time window. Rejects spirals via a max-radius-variance check.
- **GestureCalibrator** — reuses the same axis/segment math to let the user live-tune shake zones.

Both detectors guard against backward-time samples (sleep/wake, NTP adjustments) by resetting on detected clock jumps.

**GestureRouter** maps gesture events to `GestureAction`s:
- `.none`, `.toggleVisuals`
- `.simulateKeyPress(keyCode, modifiers)` — via `CGEvent`; requires Accessibility permission
- `.runShellCommand(command)` — via `Process` running `/usr/bin/env bash -c`; all shell commands are logged at `.info` level

`hyper+circle`: when a circle fires while the hyperkey chord is held, the event is queued. On hyperkey release (via `.flagsChanged`), the queued action fires.

## Settings & Persistence

- `TrailSettings` persists via `UserDefaults` (one key per property, prefixed by domain: `trail.*`, `gesture.*`, `ripple.*`, `performance.*`, `visibility.*`).
- `save()` is debounced (~300ms); `flushPendingSave()` runs on `applicationWillTerminate`.
- `apply(preset:)` temporarily suppresses callbacks, sets properties in bulk, then fires `onChanged` + `onVisibilityChanged` once.
- Gesture router config (zones + circle config) is serialized as JSON under a single UserDefaults key.
- Presets are stored as JSON files in `~/Library/Application Support/MouseTrail/Presets/`.

## Known Refactor Candidates

These are tracked in the plan file at `~/.claude/plans/ok-we-are-on-delightful-perlis.md`:

- **Split AppCore.swift** (3,066 lines → 4 files: `AppDelegate.swift`, `TrailView.swift`, `Ripple.swift`, `LogFileViewer.swift`)
- **Extract MenuBarSettingsView subviews** (1,315 lines → ~6 section views)
- **EventMonitorHub** abstraction (token-based registration, clean teardown, natural dedupe)
- **AnimationDriver protocol** (DisplayLinkDriver + TimerDriver)
- **GestureDetector protocol + ring buffer** (unifies detector scaffolding, O(1) sample pruning)
- **TrailWindowManager per-screen container** (removes per-screen state from AppDelegate)
- **SettingsEventBus protocol** (replaces the 10+ closures passed through `MouseTrailApp.swift`)
- **Separate TrailSettings model from persistence** (enables undo/redo, cleaner testing)
