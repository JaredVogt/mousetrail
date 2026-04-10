import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MouseTrail Help")
                    .font(.title.bold())
                    .padding(.bottom, 4)

                Text("This app draws a glowing trail behind your mouse cursor with hardware-accelerated rendering. All settings are saved automatically and persist between launches.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Divider()

                // MARK: - Visibility
                helpSection("Visibility") {
                    paramRow("Show Trail",
                             detail: "Toggles the mouse trail on or off. When off, the trail windows are hidden but the app keeps running in the menu bar.")
                    paramRow("Ripple Effect",
                             detail: "Enables a water-ripple distortion effect at each mouse click location. Requires Screen Recording permission to capture the screen content that gets distorted. Can be used independently of the trail.")
                }

                // MARK: - Trail Motion
                helpSection("Trail Motion") {
                    paramRow("Algorithm",
                             detail: """
                             Controls how the trail follows the cursor.
                             \u{2022} Spring \u{2014} Uses a physics-based spring simulation. The trail has a bouncy, elastic feel and overshoots slightly when the cursor stops. Feels more energetic and playful.
                             \u{2022} Smooth \u{2014} Uses delayed spline-based playback. The trail lags slightly behind the cursor (75 ms) and follows a fluid, interpolated path. Feels more graceful and calligraphic.
                             """)
                }

                // MARK: - Trail Width
                helpSection("Trail Width") {
                    paramRow("Max Width",
                             default: "8.0", range: "1 \u{2013} 20",
                             detail: "The peak thickness (in points) of the core trail line. The trail tapers from thin at the tip to this maximum width. Higher values produce a bolder, more prominent trail.")
                    paramRow("Glow Multiplier",
                             default: "3.5\u{00D7}", range: "0.5 \u{2013} 8.0\u{00D7}",
                             detail: "How wide the glow extends relative to the core trail width. At 1\u{00D7} the glow matches the core width; at higher values the glow spreads much wider, creating a more dramatic ambient halo. The glow is rendered in multiple layers (outer, middle, inner) that all scale with this multiplier.")
                }

                // MARK: - Movement
                helpSection("Movement") {
                    paramRow("Threshold",
                             default: "30 px", range: "5 \u{2013} 100 px",
                             detail: "The minimum distance (in pixels) the cursor must travel before the app starts recording a new trail segment. Higher values mean the trail only appears during deliberate, larger mouse movements, filtering out small jitter. Lower values make the trail appear for even tiny movements.")
                    paramRow("Min Velocity",
                             default: "0 px/s", range: "0 \u{2013} 200 px/s",
                             detail: "The minimum cursor speed required to draw the trail. When set above zero, the trail only appears during fast mouse movements and disappears during slow, precise movements. Useful if you want trails only during broad gestures. At 0 (default), any movement above the threshold draws a trail.")
                }

                // MARK: - Fade Duration
                helpSection("Fade Duration") {
                    paramRow("Core Trail",
                             default: "0.60 s", range: "0.1 \u{2013} 3.0 s",
                             detail: "How long the bright inner trail persists before fading to invisible. Longer values leave a lingering trail; shorter values make it disappear almost instantly. This controls the core line and its immediate shadow layers.")
                    paramRow("Glow Trail",
                             default: "0.35 s", range: "0.1 \u{2013} 2.0 s",
                             detail: "How long the outer glow layers persist. Typically set shorter than the core fade so the glow disappears first, leaving just the bright core briefly visible before it also fades. Setting this longer than the core fade creates a ghostly glow that outlasts the main trail.")
                }

                // MARK: - Trail Colors
                helpSection("Trail Colors") {
                    paramRow("Core Trail Color",
                             default: "Red (R:1.0 G:0.15 B:0.1)",
                             detail: "The color of the bright inner trail line and its immediate glow layers. Adjusted via Hue, Saturation, and Brightness sliders. The core renders as a bright, opaque line at the center of the trail.")
                    paramRow("Glow Trail Color",
                             default: "Blue (R:0.1 G:0.5 B:1.0)",
                             detail: "The color of the wider ambient glow surrounding the trail. Using a contrasting color from the core (e.g., blue glow around a red core) creates a striking two-tone effect. Using a similar color produces a more unified, monochromatic glow.")
                }

                // MARK: - Glow Opacity
                helpSection("Glow Opacity") {
                    paramRow("Outer Glow",
                             default: "0.020", range: "0.005 \u{2013} 0.150",
                             detail: "The transparency of the widest glow layer. Very subtle by default (2% opacity). Increasing this makes the outermost glow more visible, creating a larger, softer halo effect. Keep this low for a subtle ambient feel, or crank it up for a neon-like bloom.")
                    paramRow("Middle Glow",
                             default: "0.080", range: "0.02 \u{2013} 0.50",
                             detail: "The transparency of the mid-range glow layer, between the outer glow and the bright core. This layer adds depth to the glow. Higher values produce a more solid, visible glow band around the trail.")
                }

                Divider()

                // MARK: - Ripple Effect
                helpSection("Ripple Effect (detailed)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When enabled, clicking anywhere on screen creates a water-ripple distortion centered at the click location. The effect captures a circular region of the screen and applies animated concentric wave distortions.")
                            .font(.callout)

                        helpBullet("Screen Recording", "Required. The app captures a small area of the screen around each click to create the distortion. Grant permission in System Settings > Privacy & Security > Screen Recording.")
                        helpBullet("Animation", "Each ripple expands over 0.6 seconds with 4 concentric waves spaced 25 pixels apart, traveling at 150 px/s. The ripple fades out starting at 60% progress.")
                        helpBullet("Edge Behavior", "Near screen edges the ripple automatically shrinks to fit, with a minimum radius of 30 pixels. If there isn't enough room even for that, the ripple is skipped.")
                        helpBullet("Concurrency", "Up to 10 ripples can animate simultaneously. Oldest ripples are removed to make room for new ones.")
                        helpBullet("Independence", "The ripple effect works independently of the trail. You can disable the trail and use only ripples, or use both together.")
                    }
                }

                Divider()

                // MARK: - Presets
                helpSection("Presets") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Save and load named configurations of all trail parameters.")
                            .font(.callout)

                        helpBullet("Save", "Click \"Save\" to store the current settings as a new named preset.")
                        helpBullet("Load", "Select a preset from the dropdown to apply its settings.")
                        helpBullet("Modified Indicator", "An orange \"Modified\" badge appears when your current settings differ from the loaded preset. Click \"Save Changes\" to update the preset.")
                        helpBullet("Switching", "If you have unsaved changes and select a different preset, you'll be prompted to save, discard, or cancel.")
                        helpBullet("Delete", "Click the trash icon next to a preset to remove it.")
                    }
                }

                Divider()

                // MARK: - General Tips
                helpSection("General") {
                    VStack(alignment: .leading, spacing: 8) {
                        helpBullet("Menu Bar", "The app runs entirely from the menu bar with no Dock icon. Click the cursor icon in the menu bar to access settings.")
                        helpBullet("System Info", "Toggle \"Show System Info\" in the menu to see build info, mouse coordinates, active app, screen recording status, and display details.")
                        helpBullet("Multi-Monitor", "A separate trail window is created for each connected display. Trails render seamlessly across all monitors and update automatically when displays are connected or disconnected.")
                        helpBullet("Spaces & Full-Screen", "The trail and ripple windows appear on all Spaces and over full-screen apps.")
                        helpBullet("Launch at Login", "Enable the toggle in the menu to start the app automatically when you log in.")
                        helpBullet("Reset", "Click \"Reset to Defaults\" to restore all settings to their original values.")
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 400, idealHeight: 650)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func helpSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
    }

    @ViewBuilder
    private func paramRow(_ name: String, default defaultVal: String? = nil, range: String? = nil, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.subheadline.bold())
                if let defaultVal {
                    Text("Default: \(defaultVal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let range {
                    Text("Range: \(range)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func helpBullet(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .font(.callout.bold())
            Text("**\(label):** \(text)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
    }
}
