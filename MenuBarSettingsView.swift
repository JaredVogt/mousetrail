import SwiftUI
import AppKit

struct MenuBarSettingsView: View {
    @Bindable var settings: TrailSettings
    var liveInfo: LiveInfoModel
    var presetManager: PresetManager
    var onRequestPermission: () -> Void
    var onStartInfoUpdates: () -> Void
    var onStopInfoUpdates: () -> Void
    var onShowHelp: () -> Void
    var onRestart: () -> Void

    @State private var debugLogExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // MARK: - System Info
                Toggle("Show System Info", isOn: $settings.isInfoPanelVisible)

                if settings.isInfoPanelVisible {
                    VStack(alignment: .leading, spacing: 3) {
                        InfoLine("Build", value: liveInfo.buildTimestamp)
                        InfoLine("Mouse", value: "x:\(liveInfo.mouseX) y:\(liveInfo.mouseY)")
                        InfoLine("Active", value: liveInfo.frontmostApp)
                        HStack(spacing: 4) {
                            Text("Screen Recording:")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(liveInfo.screenRecordingGranted ? "✓ Granted" : "✗ Denied")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(liveInfo.screenRecordingGranted ? .green : .red)
                        }
                        InfoLine("Screens", value: "\(liveInfo.screenCount)")
                        ForEach(liveInfo.screenDescriptions, id: \.self) { desc in
                            Text(desc)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                    }
                    .padding(8)
                    .background(.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button("Request Screen Recording Permission") {
                        onRequestPermission()
                    }
                    .disabled(liveInfo.screenRecordingGranted)
                }

                Divider()

                // MARK: - Presets
                PresetSectionView(settings: settings, presetManager: presetManager)

                Divider()

                // MARK: - Visibility
                SectionHeader("Visibility")
                Toggle("Show Trail", isOn: $settings.isTrailVisible)
                Toggle("Crosshair Lines", isOn: $settings.isCrosshairVisible)
                Toggle("Ripple Effect", isOn: $settings.isRippleEnabled)
                Toggle("Hyperkey Suppresses Trail", isOn: $settings.isHyperkeyEnabled)
                    .help("Hold all four modifiers (⇧⌃⌥⌘) to suppress trail and ripple")
                Toggle("Shake to Toggle On/Off", isOn: $settings.isShakeToggleEnabled)
                    .help("Shake the mouse to temporarily hide or show all visuals")

                Divider()

                // MARK: - Trail Motion
                SectionHeader("Trail Motion")
                Picker("Algorithm", selection: $settings.trailAlgorithm) {
                    ForEach(TrailAlgorithm.allCases, id: \.self) { algorithm in
                        Text(algorithm.displayName).tag(algorithm)
                    }
                }
                .pickerStyle(.segmented)

                Divider()

                // MARK: - Trail Width
                SectionHeader("Trail Width")
                SettingsSlider("Max Width", value: $settings.maxWidth, range: 1...20, format: "%.1f")
                SettingsSlider("Glow Multiplier", value: $settings.glowWidthMultiplier, range: 0.5...8.0, format: "%.1fx")

                Divider()

                // MARK: - Movement
                SectionHeader("Movement")
                SettingsSlider("Threshold", value: $settings.movementThreshold, range: 5...100, format: "%.0f px")
                SettingsSlider("Min Velocity", value: $settings.minimumVelocity, range: 0...200, format: "%.0f px/s")

                Divider()

                // MARK: - Fade Duration
                SectionHeader("Fade Duration")
                SettingsSlider("Core Trail", value: $settings.coreFadeTime, range: 0.1...3.0, format: "%.2f s")
                SettingsSlider("Glow Trail", value: $settings.glowFadeTime, range: 0.1...2.0, format: "%.2f s")

                Divider()

                // MARK: - Colors
                SectionHeader("Trail Colors")
                InlineColorEditor("Core Trail",
                    r: $settings.coreTrailR,
                    g: $settings.coreTrailG,
                    b: $settings.coreTrailB)
                InlineColorEditor("Glow Trail",
                    r: $settings.glowTrailR,
                    g: $settings.glowTrailG,
                    b: $settings.glowTrailB)

                Divider()

                // MARK: - Glow Trail Opacity
                SectionHeader("Glow Opacity")
                SettingsSlider("Outer Glow", value: $settings.glowOuterOpacity, range: 0.005...0.15, format: "%.3f")
                SettingsSlider("Middle Glow", value: $settings.glowMiddleOpacity, range: 0.02...0.5, format: "%.3f")

                Divider()

                // MARK: - Ripple Settings
                SectionHeader("Ripple Effect")
                SettingsSlider("Radius", value: $settings.rippleRadius, range: 50...400, format: "%.0f px")
                SettingsSlider("Speed", value: $settings.rippleSpeed, range: 30...400, format: "%.0f px/s")
                SettingsSlider("Wavelength", value: $settings.rippleWavelength, range: 5...80, format: "%.0f px")
                SettingsSlider("Damping", value: $settings.rippleDamping, range: 0.5...6.0, format: "%.1f")
                SettingsSlider("Amplitude", value: $settings.rippleAmplitude, range: 2...30, format: "%.0f px")
                SettingsSlider("Duration", value: $settings.rippleDuration, range: 0.3...3.0, format: "%.1f s")
                SettingsSlider("Specular", value: $settings.rippleSpecularIntensity, range: 0...2.0, format: "%.2f")

                Divider()

                // MARK: - Performance Experiments
                DisclosureGroup("Performance Experiments") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Toggle one experiment at a time to compare CPU cost against visual impact.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        PerformanceExperimentToggle(
                            "Reduce synthetic sample rate",
                            description: "Drop synthetic trail emission from 240 Hz to 120 Hz.",
                            isOn: $settings.reduceSyntheticSampleRate
                        )
                        PerformanceExperimentToggle(
                            "Enable smooth input coalescing",
                            description: "Keep coalesced mouse events on in smooth mode.",
                            isOn: $settings.enableSmoothInputCoalescing
                        )
                        PerformanceExperimentToggle(
                            "Use reduced layer stack",
                            description: "Skip the outer glow layers and render a cheaper trail stack.",
                            isOn: $settings.useReducedLayerStack
                        )
                        PerformanceExperimentToggle(
                            "Only update dirty screens",
                            description: "Render only screens that still have active trail content.",
                            isOn: $settings.onlyUpdateDirtyScreens
                        )
                        PerformanceExperimentToggle(
                            "Use linear smooth playback lookup",
                            description: "Avoid rescanning the raw sample array from the beginning.",
                            isOn: $settings.useLinearSmoothPlaybackLookup
                        )
                        PerformanceExperimentToggle(
                            "Use stronger point decimation",
                            description: "Accept fewer points before rebuilding the path.",
                            isOn: $settings.useStrongerPointDecimation
                        )
                        PerformanceExperimentToggle(
                            "Use relaxed path rebuild",
                            description: "Use fewer points and lighter smoothing when fitting the trail path.",
                            isOn: $settings.useRelaxedPathRebuild
                        )
                        PerformanceExperimentToggle(
                            "Cap trail rendering to 60 FPS",
                            description: "Throttle path rebuilds while leaving input processing live.",
                            isOn: $settings.capTrailRenderingTo60FPS
                        )

                        HStack {
                            Button("All Off") {
                                settings.setAllPerformanceExperiments(enabled: false)
                            }
                            Button("All On") {
                                settings.setAllPerformanceExperiments(enabled: true)
                            }
                            Spacer()
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }

                Divider()

                // MARK: - Debug Log
                Picker("Log Level", selection: $settings.logLevelRaw) {
                    ForEach(LogLevel.allCases, id: \.rawValue) { level in
                        Text(level.label).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                DisclosureGroup("Debug Log", isExpanded: $debugLogExpanded) {
                    ScrollView {
                        Text(DebugLogger.shared.displayText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 150)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    HStack {
                        Button("Clear") {
                            DebugLogger.shared.clear()
                        }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                DebugLogger.shared.getAllMessages(), forType: .string)
                        }
                        Spacer()
                    }
                }

                Divider()

                // MARK: - Actions
                HStack {
                    Button("Reset to Defaults") {
                        settings.resetToDefaults()
                        presetManager.activePresetID = nil
                        presetManager.takeCleanSnapshot(from: settings)
                    }
                    Spacer()
                }

                Divider()

                // MARK: - Footer
                Toggle("Launch at Login", isOn: Binding(
                    get: { LaunchAtLoginService.shared.isEnabled },
                    set: { _ in LaunchAtLoginService.shared.toggle() }
                ))

                Button("View README") {
                    onShowHelp()
                }

                Button("Restart") {
                    onRestart()
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(12)
        }
        .frame(width: 320, height: 700)
        .onAppear { onStartInfoUpdates() }
        .onDisappear { onStopInfoUpdates() }
    }
}

// MARK: - Preset Section

private enum PresetMode {
    case normal
    case saving
    case confirmSwitch
    case confirmDelete
}

private struct PresetSectionView: View {
    @Bindable var settings: TrailSettings
    var presetManager: PresetManager

    @State private var mode: PresetMode = .normal
    @State private var newPresetName = ""
    @State private var pendingPresetID: UUID?

    private var presetBinding: Binding<UUID?> {
        Binding(
            get: { presetManager.activePresetID },
            set: { newID in
                guard newID != presetManager.activePresetID else { return }
                if presetManager.activePresetID != nil,
                   presetManager.hasUnsavedChanges(relativeTo: settings) {
                    pendingPresetID = newID
                    mode = .confirmSwitch
                } else {
                    switchToPreset(newID)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Presets")

            // Picker row
            HStack(spacing: 6) {
                Picker("", selection: presetBinding) {
                    Text("(none)").tag(nil as UUID?)
                    ForEach(presetManager.presets) { preset in
                        Text(preset.name).tag(preset.id as UUID?)
                    }
                }
                .labelsHidden()
                .disabled(mode != .normal)

                Spacer()

                if presetManager.activePresetID != nil, mode == .normal {
                    Button(role: .destructive) {
                        mode = .confirmDelete
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete preset")
                }

                if mode == .normal {
                    Button("Save") {
                        newPresetName = ""
                        mode = .saving
                    }
                    .help("Save as new preset")
                }
            }

            // Inline save field
            if mode == .saving {
                HStack(spacing: 6) {
                    TextField("Preset name", text: $newPresetName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { commitSave() }
                    Button("OK") { commitSave() }
                        .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { mode = .normal }
                }
            }

            // Unsaved changes warning when switching
            if mode == .confirmSwitch {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You have unsaved changes.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    HStack(spacing: 6) {
                        Button("Save & Switch") {
                            if let id = presetManager.activePresetID {
                                presetManager.updatePreset(id: id, from: settings)
                            }
                            switchToPreset(pendingPresetID)
                            pendingPresetID = nil
                            mode = .normal
                        }
                        Button("Discard") {
                            switchToPreset(pendingPresetID)
                            pendingPresetID = nil
                            mode = .normal
                        }
                        Button("Cancel") {
                            pendingPresetID = nil
                            mode = .normal
                        }
                    }
                    .controlSize(.small)
                }
            }

            // Delete confirmation
            if mode == .confirmDelete {
                HStack(spacing: 6) {
                    Text("Delete this preset?")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Delete", role: .destructive) {
                        if let id = presetManager.activePresetID {
                            presetManager.deletePreset(id: id)
                        }
                        mode = .normal
                    }
                    Button("Cancel") { mode = .normal }
                }
                .controlSize(.small)
            }

            // Modified indicator (only in normal mode)
            if mode == .normal,
               presetManager.activePresetID != nil,
               presetManager.hasUnsavedChanges(relativeTo: settings) {
                HStack {
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Save Changes") {
                        if let id = presetManager.activePresetID {
                            presetManager.updatePreset(id: id, from: settings)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func commitSave() {
        let trimmed = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        presetManager.saveNewPreset(name: trimmed, from: settings)
        newPresetName = ""
        mode = .normal
    }

    private func switchToPreset(_ id: UUID?) {
        if let id, let preset = presetManager.presets.first(where: { $0.id == id }) {
            presetManager.applyPreset(preset, to: settings)
        } else {
            presetManager.activePresetID = nil
            presetManager.takeCleanSnapshot(from: settings)
        }
    }
}

// MARK: - Reusable Components

private struct InfoLine: View {
    let label: String
    let value: String
    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
        }
    }
}

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

private struct PerformanceExperimentToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    init(_ title: String, description: String, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: $isOn)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InlineColorEditor: View {
    let label: String
    @Binding var r: Double
    @Binding var g: Double
    @Binding var b: Double
    @State private var expanded = false

    init(_ label: String, r: Binding<Double>, g: Binding<Double>, b: Binding<Double>) {
        self.label = label
        self._r = r
        self._g = g
        self._b = b
    }

    // Convert RGB to HSB
    private var hue: Double {
        NSColor(red: r, green: g, blue: b, alpha: 1).hueComponent
    }
    private var saturation: Double {
        NSColor(red: r, green: g, blue: b, alpha: 1).saturationComponent
    }
    private var brightness: Double {
        NSColor(red: r, green: g, blue: b, alpha: 1).brightnessComponent
    }

    private func setHSB(h: Double, s: Double, b bright: Double) {
        let c = NSColor(hue: h, saturation: s, brightness: bright, alpha: 1)
            .usingColorSpace(.sRGB) ?? NSColor(hue: h, saturation: s, brightness: bright, alpha: 1)
        r = c.redComponent
        g = c.greenComponent
        b = c.blueComponent
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 8) {
                // Hue slider with rainbow gradient
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HueSlider(hue: Binding(
                        get: { hue },
                        set: { setHSB(h: $0, s: saturation, b: brightness) }
                    ))
                    .frame(height: 20)
                }

                // Saturation slider
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saturation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    GradientSlider(
                        value: Binding(
                            get: { saturation },
                            set: { setHSB(h: hue, s: $0, b: brightness) }
                        ),
                        left: Color(hue: hue, saturation: 0, brightness: brightness),
                        right: Color(hue: hue, saturation: 1, brightness: brightness)
                    )
                    .frame(height: 20)
                }

                // Brightness slider
                VStack(alignment: .leading, spacing: 2) {
                    Text("Brightness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    GradientSlider(
                        value: Binding(
                            get: { brightness },
                            set: { setHSB(h: hue, s: saturation, b: $0) }
                        ),
                        left: Color.black,
                        right: Color(hue: hue, saturation: saturation, brightness: 1)
                    )
                    .frame(height: 20)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: r, green: g, blue: b))
                    .frame(width: 24, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.secondary.opacity(0.4), lineWidth: 1)
                    )
            }
        }
    }
}

// MARK: - Custom Color Sliders

private struct HueSlider: View {
    @Binding var hue: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Rainbow gradient track
                LinearGradient(
                    colors: (0...10).map { Color(hue: Double($0) / 10.0, saturation: 1, brightness: 1) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Thumb
                Circle()
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(radius: 1)
                    .offset(x: hue * (geo.size.width - 16))
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                hue = max(0, min(1, value.location.x / geo.size.width))
            })
        }
    }
}

private struct GradientSlider: View {
    @Binding var value: Double
    let left: Color
    let right: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(colors: [left, right], startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Circle()
                    .fill(Color(
                        hue: 0, saturation: 0, brightness: value > 0.5 ? 0 : 1
                    ).opacity(0.01)) // invisible fill, border does the work
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(radius: 1)
                    .offset(x: value * (geo.size.width - 16))
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                self.value = max(0, min(1, value.location.x / geo.size.width))
            })
        }
    }
}
