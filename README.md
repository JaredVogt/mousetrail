# MouseTrail

A macOS menu bar application that renders a hardware-accelerated glowing trail behind your mouse cursor, with click ripple effects, full-screen crosshair lines, and gesture-based controls.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)
![Language](https://img.shields.io/badge/language-Swift-orange.svg)

## Features

### Glowing Mouse Trail
- Hardware-accelerated trail rendering using Core Animation and CAShapeLayer
- Catmull-Rom spline interpolation for smooth curves
- Triple-layer glow effect: outer glow, middle glow, and bright core
- Two trail algorithms: **Smooth** (direct path following) and **Spring** (physics-based springy motion)
- Configurable trail width, fade duration, glow opacity, and colors (core + glow, via HSB picker)
- Time-based fading with independent core and glow fade times
- Movement threshold and minimum velocity filters

### Click Ripple Effect
- Metal shader-powered ripple distortion effect on mouse click
- Captures the screen area under the click and applies a water-ripple distortion
- Configurable radius, speed, wavelength, damping, amplitude, duration, and specular lighting
- Automatically suppressed during click-drag operations

### Full-Screen Crosshair
- Optional crosshair lines that follow the mouse cursor across the entire screen
- Togglable from the settings panel

### Gesture Controls
- **Shake to toggle**: Rapidly shake the mouse to hide/show all visuals
- **Circle gesture**: Draw two circles with the mouse to trigger a configurable hotkey (default: ⇧⌃⌘4)
- **Hyper+circle gesture**: Hold all four modifiers (⇧⌃⌥⌘) while drawing circles to trigger a second hotkey (⇧⌃⌘2) on release

### Menu Bar Settings Panel
- Full SwiftUI settings panel accessible from the menu bar icon
- Real-time controls for all trail, ripple, and visibility settings
- Inline HSB color pickers for core and glow trail colors
- Preset system: save and recall named configurations
- Restart and Quit buttons
- Help window with README viewer

### Multi-Monitor Support
- Separate trail window per connected display for seamless rendering
- Automatic detection when monitors are connected or disconnected
- Trail renders continuously across all screens

## Installation

### Building from Source

#### Prerequisites
- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Apple Development signing identity (for Accessibility permissions to persist across rebuilds)

#### Build
```bash
git clone https://github.com/JaredVogt/mousetrail.git
cd mousetrail
./build-working.sh
```

The build script compiles the Metal shader, builds all Swift sources, creates a signed `.app` bundle, installs to `/Applications`, and launches the app.

## Usage

The app runs as a menu bar application (no Dock icon). Click the menu bar icon to access settings.

### Gesture Controls

| Gesture | Action |
|---------|--------|
| Shake mouse rapidly | Toggle all visuals on/off |
| Draw two circles | Trigger hotkey (⇧⌃⌘4) |
| Hold ⇧⌃⌥⌘ + draw circles | Trigger hotkey (⇧⌃⌘2) on release |

### Settings

All settings are accessible from the menu bar panel:

- **Visibility**: Toggle trail, crosshair, ripple, and shake-to-toggle
- **Trail Motion**: Choose between Smooth and Spring algorithms
- **Trail Width**: Max width and glow multiplier
- **Movement**: Threshold distance and minimum velocity
- **Fade Duration**: Independent core and glow fade times
- **Colors**: HSB color pickers for core and glow trails
- **Glow Opacity**: Outer and middle glow intensity
- **Ripple Effect**: Radius, speed, wavelength, damping, amplitude, duration, specular intensity
- **Presets**: Save/load named configurations

## Permissions

The app shows a warning banner in the settings panel when permissions are missing.

- **Accessibility**: Required for circle gesture hotkeys (simulates keypresses via `CGEvent`). Grant in **System Settings > Privacy & Security > Accessibility**.
- **Screen Recording**: Required for the ripple effect (captures screen content for distortion). Grant in **System Settings > Privacy & Security > Screen Recording**.
- Mouse tracking, trail rendering, and keyboard modifier monitoring use public APIs and do not require special permissions.

## Architecture

The app is structured across multiple Swift source files:

| File | Purpose |
|------|---------|
| `MouseTrailApp.swift` | App entry point and SwiftUI MenuBarExtra |
| `AppCore.swift` | Main app delegate, event monitoring, trail coordination |
| `MenuBarSettingsView.swift` | SwiftUI settings panel |
| `TrailSettings.swift` | Persisted settings with UserDefaults |
| `TrailPreset.swift` | Preset data model (Codable) |
| `PresetManager.swift` | Preset save/load/delete |
| `ShakeDetector.swift` | Mouse shake gesture detection |
| `CircleGestureDetector.swift` | Two-circle gesture detection |
| `HelpView.swift` | README viewer window |
| `LiveInfoModel.swift` | System info model |
| `LaunchAtLoginService.swift` | Launch at login support |
| `RippleKernel.ci.metal` | Metal CIKernel for ripple distortion |

## Privacy

- No data is stored or transmitted externally
- All processing happens locally
- Settings are stored in UserDefaults
- Presets are stored in `~/Library/Application Support/MouseTrail/`