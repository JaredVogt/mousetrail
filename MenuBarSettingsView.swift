import SwiftUI

struct MenuBarSettingsView: View {
    @Bindable var settings: TrailSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // MARK: - Visibility
                SectionHeader("Visibility")
                Toggle("Show Trail", isOn: $settings.isTrailVisible)
                Toggle("Show Info Panel", isOn: $settings.isInfoPanelVisible)
                Toggle("Ripple Effect", isOn: $settings.isRippleEnabled)

                Divider()

                // MARK: - Trail Width
                SectionHeader("Trail Width")
                SettingsSlider("Max Width", value: $settings.maxWidth, range: 1...20, format: "%.1f")
                SettingsSlider("Blue Multiplier", value: $settings.blueWidthMultiplier, range: 0.5...8.0, format: "%.1fx")

                Divider()

                // MARK: - Movement
                SectionHeader("Movement")
                SettingsSlider("Threshold", value: $settings.movementThreshold, range: 5...100, format: "%.0f px")
                SettingsSlider("Min Velocity", value: $settings.minimumVelocity, range: 0...200, format: "%.0f px/s")

                Divider()

                // MARK: - Fade Duration
                SectionHeader("Fade Duration")
                SettingsSlider("Red Trail", value: $settings.redFadeTime, range: 0.1...3.0, format: "%.2f s")
                SettingsSlider("Blue Trail", value: $settings.blueFadeTime, range: 0.1...2.0, format: "%.2f s")

                Divider()

                // MARK: - Colors
                SectionHeader("Trail Colors")
                HStack {
                    ColorPicker("Red Trail", selection: $settings.redTrailColor, supportsOpacity: false)
                    Spacer()
                    ColorPicker("Blue Trail", selection: $settings.blueTrailColor, supportsOpacity: false)
                }

                Divider()

                // MARK: - Blue Trail Opacity
                SectionHeader("Blue Glow Opacity")
                SettingsSlider("Outer Glow", value: $settings.blueOuterOpacity, range: 0.005...0.15, format: "%.3f")
                SettingsSlider("Middle Glow", value: $settings.blueMiddleOpacity, range: 0.02...0.5, format: "%.3f")

                Divider()

                // MARK: - Actions
                HStack {
                    Button("Reset to Defaults") {
                        settings.resetToDefaults()
                    }
                    Spacer()
                }

                Divider()

                // MARK: - Footer
                Toggle("Launch at Login", isOn: Binding(
                    get: { LaunchAtLoginService.shared.isEnabled },
                    set: { _ in LaunchAtLoginService.shared.toggle() }
                ))

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(12)
        }
        .frame(width: 300, height: 480)
    }
}

// MARK: - Reusable Components

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

private struct SettingsSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String = "%.2f") {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: format, value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
