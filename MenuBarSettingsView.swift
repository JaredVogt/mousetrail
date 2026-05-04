import SwiftUI
import AppKit

struct MenuBarSettingsView: View {
    @Bindable var settings: TrailSettings
    var liveInfo: LiveInfoModel
    var presetManager: PresetManager
    /// Dispatches settings actions (permissions, calibration, restart, ...)
    /// back to the app delegate.
    unowned var bus: any SettingsEventBus

    @State private var debugLogExpanded = false
    @State private var gestureSettingsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PermissionsBannerSection(liveInfo: liveInfo, bus: bus)

                SystemInfoSection(settings: settings, liveInfo: liveInfo)

                Divider()

                PresetSectionView(settings: settings, presetManager: presetManager)

                Divider()

                VisibilitySection(settings: settings, bus: bus)

                Divider()

                TrailMotionSection(settings: settings)

                Divider()

                TrailColorsSection(settings: settings)

                Divider()

                RippleSection(settings: settings)

                Divider()

                PerformanceExperimentsSection(settings: settings)

                Divider()

                DebugLogSection(settings: settings, debugLogExpanded: $debugLogExpanded)

                Divider()

                ActionsAndFooterSection(
                    settings: settings,
                    presetManager: presetManager,
                    bus: bus
                )
            }
            .padding(12)
        }
        .frame(width: 320, height: 700)
        .onAppear { bus.startInfoUpdates() }
        .onDisappear { bus.stopInfoUpdates() }
    }
}

// MARK: - Permissions Banner

private struct PermissionsBannerSection: View {
    var liveInfo: LiveInfoModel
    unowned var bus: any SettingsEventBus

    var body: some View {
        if !liveInfo.screenRecordingGranted || !liveInfo.accessibilityGranted {
            VStack(alignment: .leading, spacing: 6) {
                Text("Permissions Needed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)

                if !liveInfo.screenRecordingGranted {
                    HStack {
                        Text("✗ Screen Recording")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Grant") { bus.requestScreenRecordingPermission() }
                            .controlSize(.small)
                    }
                    Text("Required for ripple effect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !liveInfo.accessibilityGranted {
                    HStack {
                        Text("✗ Accessibility")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Grant") { bus.requestAccessibilityPermission() }
                            .controlSize(.small)
                    }
                    Text("Required for circle gesture hotkeys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.orange.opacity(0.3)))
        }
    }
}

// MARK: - System Info

private struct SystemInfoSection: View {
    @Bindable var settings: TrailSettings
    var liveInfo: LiveInfoModel

    var body: some View {
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
                HStack(spacing: 4) {
                    Text("Accessibility:")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(liveInfo.accessibilityGranted ? "✓ Granted" : "✗ Denied")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(liveInfo.accessibilityGranted ? .green : .red)
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
        }
    }
}

// MARK: - Visibility

private struct VisibilitySection: View {
    @Bindable var settings: TrailSettings
    unowned var bus: any SettingsEventBus

    var body: some View {
        SectionHeader("Visibility")
        Toggle("Show Trail", isOn: $settings.isTrailVisible)
        Toggle("Crosshair Lines", isOn: $settings.isCrosshairVisible)
        if settings.isCrosshairVisible {
            InlineColorEditor("Crosshair Color",
                r: $settings.crosshairR,
                g: $settings.crosshairG,
                b: $settings.crosshairB)
            SettingsSlider("Opacity", value: $settings.crosshairOpacity, range: 0.05...1.0, format: "%.2f")
            SettingsSlider("Line Width", value: $settings.crosshairLineWidth, range: 0.5...5.0, format: "%.1f px")
        }
        Toggle("Ripple Effect", isOn: $settings.isRippleEnabled)
        Toggle("Shake Gestures", isOn: $settings.isShakeToggleEnabled)
            .help("Enable directional shake gestures to trigger actions")

        if settings.isShakeToggleEnabled {
            GestureSettingsSection(
                settings: settings,
                getRouter: { bus.currentGestureRouter() },
                setRouter: { bus.updateGestureRouter($0) },
                getCalibrationSession: { bus.currentCalibrationSession() },
                startCalibration: { bus.startCalibration() }
            )
        }
    }
}

// MARK: - Trail Motion

private struct TrailMotionSection: View {
    @Bindable var settings: TrailSettings

    var body: some View {
        SectionHeader("Trail Motion")
        Picker("Algorithm", selection: $settings.trailAlgorithm) {
            ForEach(TrailAlgorithm.allCases, id: \.self) { algorithm in
                Text(algorithm.displayName).tag(algorithm)
            }
        }
        .pickerStyle(.segmented)

        Divider()

        SectionHeader("Trail Width")
        SettingsSlider("Max Width", value: $settings.maxWidth, range: 1...20, format: "%.1f")
        SettingsSlider("Glow Multiplier", value: $settings.glowWidthMultiplier, range: 0.5...8.0, format: "%.1fx")

        Divider()

        SectionHeader("Movement")
        SettingsSlider("Threshold", value: $settings.movementThreshold, range: 5...100, format: "%.0f px")
        SettingsSlider("Min Velocity", value: $settings.minimumVelocity, range: 0...200, format: "%.0f px/s")

        Divider()

        SectionHeader("Fade Duration")
        SettingsSlider("Core Trail", value: $settings.coreFadeTime, range: 0.1...3.0, format: "%.2f s")
        SettingsSlider("Glow Trail", value: $settings.glowFadeTime, range: 0.1...2.0, format: "%.2f s")
    }
}

// MARK: - Trail Colors

private struct TrailColorsSection: View {
    @Bindable var settings: TrailSettings

    var body: some View {
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

        SectionHeader("Glow Opacity")
        SettingsSlider("Outer Glow", value: $settings.glowOuterOpacity, range: 0.005...0.15, format: "%.3f")
        SettingsSlider("Middle Glow", value: $settings.glowMiddleOpacity, range: 0.02...0.5, format: "%.3f")
    }
}

// MARK: - Ripple

private struct RippleSection: View {
    @Bindable var settings: TrailSettings

    var body: some View {
        SectionHeader("Ripple Effect")
        SettingsSlider("Radius", value: $settings.rippleRadius, range: 50...400, format: "%.0f px")
        SettingsSlider("Speed", value: $settings.rippleSpeed, range: 30...400, format: "%.0f px/s")
        SettingsSlider("Wavelength", value: $settings.rippleWavelength, range: 5...80, format: "%.0f px")
        SettingsSlider("Damping", value: $settings.rippleDamping, range: 0.5...6.0, format: "%.1f")
        SettingsSlider("Amplitude", value: $settings.rippleAmplitude, range: 2...30, format: "%.0f px")
        SettingsSlider("Duration", value: $settings.rippleDuration, range: 0.3...3.0, format: "%.1f s")
        SettingsSlider("Specular", value: $settings.rippleSpecularIntensity, range: 0...2.0, format: "%.2f")
    }
}

// MARK: - Performance Experiments

private struct PerformanceExperimentsSection: View {
    @Bindable var settings: TrailSettings

    var body: some View {
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
                    "Disable layer shadow blur",
                    description: "Skip the per-layer Gaussian blur. Trail edges will look harder but the GPU offscreen blur passes are eliminated — biggest perf win on high-DPI screens.",
                    isOn: $settings.disableLayerShadows
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
    }
}

// MARK: - Debug Log

private struct DebugLogSection: View {
    @Bindable var settings: TrailSettings
    @Binding var debugLogExpanded: Bool

    var body: some View {
        Picker("Log Level", selection: $settings.logLevelRaw) {
            ForEach(LogLevel.allCases, id: \.rawValue) { level in
                Text(level.label).tag(level.rawValue)
            }
        }
        .pickerStyle(.segmented)

        DisclosureGroup("Debug Log", isExpanded: $debugLogExpanded) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(LogFileViewer.shared.lines.reversed()) { line in
                            Text(line.text)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(logLineColor(line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(4)
                }
                .onChange(of: LogFileViewer.shared.lines.last?.id) { _, newID in
                    if let id = newID {
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
            .frame(height: 150)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                Button("Clear") {
                    LogFileViewer.shared.clear()
                }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        LogFileViewer.shared.getAllText(), forType: .string)
                }
                Spacer()
            }
        }
    }

    private func logLineColor(_ kind: LogFileViewer.LogLine.Kind) -> Color {
        switch kind {
        case .restart: return .cyan
        case .error: return .red
        case .debug: return .gray
        case .info: return .green
        }
    }
}

// MARK: - Actions & Footer

private struct ActionsAndFooterSection: View {
    @Bindable var settings: TrailSettings
    var presetManager: PresetManager
    unowned var bus: any SettingsEventBus

    var body: some View {
        HStack {
            Button("Reset to Defaults") {
                settings.resetToDefaults()
                presetManager.activePresetID = nil
                presetManager.takeCleanSnapshot(from: settings)
            }
            Spacer()
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { LaunchAtLoginService.shared.isEnabled },
            set: { _ in LaunchAtLoginService.shared.toggle() }
        ))

        Button("View README") {
            bus.showHelpWindow()
        }

        Button("Restart") {
            bus.restart()
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
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

// MARK: - Gesture Settings

private struct GestureSettingsSection: View {
    @Bindable var settings: TrailSettings
    var getRouter: () -> GestureRouter
    var setRouter: (GestureRouter) -> Void
    var getCalibrationSession: () -> CalibrationSession?
    var startCalibration: () -> CalibrationSession

    @State private var shakeZones: [ShakeZone] = []
    @State private var circleConfig = CircleGestureConfig()
    @State private var editingZoneID: UUID? = nil
    @State private var calibrationState: CalibrationUIState = .idle
    @State private var advancedExpanded = false

    private enum CalibrationUIState: Equatable {
        case idle
        case recording(sampleCount: Int)
        case result(angleDeg: CGFloat, spreadDeg: CGFloat, toleranceDeg: CGFloat, reversals: Int)
        case failed(String)

        static func == (lhs: CalibrationUIState, rhs: CalibrationUIState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.recording(let a), .recording(let b)): return a == b
            case (.result(let a1, let a2, let a3, let a4), .result(let b1, let b2, let b3, let b4)):
                return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Shake Zones")
            Text("Each direction triggers a different action")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($shakeZones) { $zone in
                ShakeZoneRow(
                    zone: $zone,
                    isEditing: editingZoneID == zone.id,
                    onToggleEdit: {
                        editingZoneID = editingZoneID == zone.id ? nil : zone.id
                    },
                    onDelete: {
                        shakeZones.removeAll { $0.id == zone.id }
                        commitChanges()
                    }
                )
                .onChange(of: zone) { _, _ in commitChanges() }
            }

            HStack {
                Button("Add Zone") {
                    let newZone = ShakeZone(
                        id: UUID(),
                        name: "New Shake",
                        centerAngleDegrees: 0,
                        toleranceDegrees: 20,
                        action: .none,
                        isEnabled: true
                    )
                    shakeZones.append(newZone)
                    editingZoneID = newZone.id
                    commitChanges()
                }
                .controlSize(.small)

                Button("Learn Zone") {
                    startCalibrationRecording()
                }
                .controlSize(.small)
            }

            // Calibration UI
            switch calibrationState {
            case .idle:
                EmptyView()
            case .recording(let count):
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Recording... (\(count) samples)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Stop") {
                        getCalibrationSession()?.stopRecording()
                    }
                    .controlSize(.mini)
                }
                .padding(6)
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            case .result(let angle, let spread, let tolerance, let reversals):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected shake:")
                        .font(.caption.bold())
                    Text("Axis: \(Int(angle))\u{00B0}  Spread: \u{00B1}\(String(format: "%.1f", spread))\u{00B0}  Reversals: \(reversals)")
                        .font(.system(size: 10, design: .monospaced))
                    Text("Suggested tolerance: \u{00B1}\(Int(tolerance))\u{00B0}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Create Zone") {
                            let newZone = ShakeZone(
                                id: UUID(),
                                name: directionName(for: angle),
                                centerAngleDegrees: angle,
                                toleranceDegrees: tolerance,
                                action: .none,
                                isEnabled: true
                            )
                            shakeZones.append(newZone)
                            editingZoneID = newZone.id
                            commitChanges()
                            calibrationState = .idle
                        }
                        .controlSize(.small)
                        Button("Discard") {
                            calibrationState = .idle
                        }
                        .controlSize(.small)
                    }
                }
                .padding(6)
                .background(.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Dismiss") {
                        calibrationState = .idle
                    }
                    .controlSize(.mini)
                }
                .padding(6)
                .background(.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Divider()

            SectionHeader("Circle Gesture")
            Toggle("Enabled", isOn: $circleConfig.isEnabled)
                .onChange(of: circleConfig.isEnabled) { _, _ in commitChanges() }

            if circleConfig.isEnabled {
                Toggle("Distinguish CW/CCW", isOn: $circleConfig.directionMatters)
                    .onChange(of: circleConfig.directionMatters) { _, _ in commitChanges() }

                GestureActionPicker(
                    label: circleConfig.directionMatters ? "Clockwise" : "Circle",
                    action: $circleConfig.clockwiseAction
                )
                .onChange(of: circleConfig.clockwiseAction) { _, _ in commitChanges() }

                if circleConfig.directionMatters {
                    GestureActionPicker(
                        label: "Counter-CW",
                        action: $circleConfig.counterClockwiseAction
                    )
                    .onChange(of: circleConfig.counterClockwiseAction) { _, _ in commitChanges() }
                }
            }

            Divider()

            DisclosureGroup("Advanced Parameters", isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shake Detector")
                        .font(.caption.bold())
                    SettingsSlider("Time Window", value: $settings.shakeTimeWindow, range: 0.2...2.0, format: "%.2f s")
                    HStack {
                        Text("Required Reversals")
                            .font(.subheadline)
                        Spacer()
                        Stepper("\(settings.shakeRequiredReversals)", value: $settings.shakeRequiredReversals, in: 1...10)
                            .font(.subheadline.monospacedDigit())
                    }
                    SettingsSlider("Min Displacement", value: $settings.shakeMinDisplacement, range: 10...200, format: "%.0f pt")
                    SettingsSlider("Min Velocity", value: $settings.shakeMinVelocity, range: 100...2000, format: "%.0f pt/s")
                    SettingsSlider("Cooldown", value: $settings.shakeCooldown, range: 0.1...5.0, format: "%.1f s")
                    SettingsSlider("Angular Tolerance", value: $settings.shakeAngularTolerance, range: 5...90, format: "%.0f\u{00B0}")

                    Divider()

                    Text("Circle Detector")
                        .font(.caption.bold())
                    SettingsSlider("Circle Time Window", value: $settings.circleTimeWindow, range: 1.0...10.0, format: "%.1f s")
                    SettingsSlider("Sample Window", value: $settings.circleSampleWindow, range: 0.5...5.0, format: "%.1f s")
                    SettingsSlider("Min Radius", value: $settings.circleMinRadius, range: 10...100, format: "%.0f pt")
                    SettingsSlider("Min Speed", value: $settings.circleMinSpeed, range: 50...500, format: "%.0f pt/s")
                    SettingsSlider("Cooldown", value: $settings.circleCooldown, range: 0.5...5.0, format: "%.1f s")
                    HStack {
                        Text("Required Circles")
                            .font(.subheadline)
                        Spacer()
                        Stepper("\(settings.circleRequiredCircles)", value: $settings.circleRequiredCircles, in: 1...5)
                            .font(.subheadline.monospacedDigit())
                    }
                    SettingsSlider("Max Radius Variance", value: $settings.circleMaxRadiusVariance, range: 1.5...10.0, format: "%.1fx")
                }
                .padding(.top, 4)
            }
        }
        .padding(.leading, 8)
        .onAppear { loadFromRouter() }
    }

    private func loadFromRouter() {
        let router = getRouter()
        shakeZones = router.shakeZones
        circleConfig = router.circleConfig
    }

    private func commitChanges() {
        var router = getRouter()
        router.shakeZones = shakeZones
        router.circleConfig = circleConfig
        setRouter(router)
    }

    private func startCalibrationRecording() {
        let session = startCalibration()
        session.onStateChanged = { state in
            DispatchQueue.main.async {
                switch state {
                case .idle:
                    calibrationState = .idle
                case .recording:
                    calibrationState = .recording(sampleCount: session.sampleCount)
                case .analyzing:
                    calibrationState = .recording(sampleCount: session.sampleCount)
                case .complete(let result):
                    calibrationState = .result(
                        angleDeg: result.axisAngleDegrees,
                        spreadDeg: result.angularSpreadDegrees,
                        toleranceDeg: result.suggestedToleranceDegrees,
                        reversals: result.reversals
                    )
                case .failed(let msg):
                    calibrationState = .failed(msg)
                }
            }
        }
        session.startRecording()
        calibrationState = .recording(sampleCount: 0)
    }

    private func directionName(for angleDeg: CGFloat) -> String {
        let angle = Int(angleDeg)
        switch angle {
        case 0...10, 170...180: return "Horizontal Shake"
        case 80...100: return "Vertical Shake"
        case 35...55: return "Diagonal Up Shake"
        case 125...145: return "Diagonal Down Shake"
        default: return "Shake \(angle)\u{00B0}"
        }
    }
}

private struct ShakeZoneRow: View {
    @Binding var zone: ShakeZone
    let isEditing: Bool
    var onToggleEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: $zone.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Text(zone.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(zone.isEnabled ? .primary : .secondary)

                Spacer()

                Text(angleLabel(zone.centerAngleDegrees))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button(isEditing ? "Done" : "Edit") {
                    onToggleEdit()
                }
                .controlSize(.mini)
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Name", text: $zone.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))

                    HStack {
                        Text("Angle")
                            .font(.caption)
                        Slider(value: $zone.centerAngleDegrees, in: 0...179)
                        Text("\(Int(zone.centerAngleDegrees))\u{00B0}")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 30, alignment: .trailing)
                    }

                    HStack {
                        Text("Tolerance")
                            .font(.caption)
                        Slider(value: $zone.toleranceDegrees, in: 5...45)
                        Text("\u{00B1}\(Int(zone.toleranceDegrees))\u{00B0}")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 30, alignment: .trailing)
                    }

                    GestureActionPicker(label: "Action", action: $zone.action)

                    Button("Delete Zone") {
                        onDelete()
                    }
                    .foregroundStyle(.red)
                    .controlSize(.mini)
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func angleLabel(_ degrees: CGFloat) -> String {
        switch Int(degrees) {
        case 0: return "0\u{00B0} (H)"
        case 45: return "45\u{00B0} (\u{2197})"
        case 90: return "90\u{00B0} (V)"
        case 135: return "135\u{00B0} (\u{2198})"
        default: return "\(Int(degrees))\u{00B0}"
        }
    }
}

// MARK: - Key Code Mapping

/// Maps characters to macOS virtual key codes.
private let characterToKeyCode: [Character: UInt16] = [
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
    "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
    "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12,
    "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
    "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
    "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25,
    "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29, "\\": 0x2A, ",": 0x2B,
    "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
]

/// Reverse lookup: key code to display character.
private let keyCodeToCharacter: [UInt16: String] = {
    var map: [UInt16: String] = [:]
    for (char, code) in characterToKeyCode {
        map[code] = String(char)
    }
    // Special keys
    map[0x24] = "Return"
    map[0x30] = "Tab"
    map[0x31] = "Space"
    map[0x33] = "Delete"
    map[0x35] = "Escape"
    map[0x7A] = "F1"
    map[0x78] = "F2"
    map[0x63] = "F3"
    map[0x76] = "F4"
    map[0x60] = "F5"
    map[0x61] = "F6"
    map[0x62] = "F7"
    map[0x64] = "F8"
    map[0x65] = "F9"
    map[0x6D] = "F10"
    map[0x67] = "F11"
    map[0x6F] = "F12"
    map[0x7B] = "\u{2190}" // left arrow
    map[0x7C] = "\u{2192}" // right arrow
    map[0x7D] = "\u{2193}" // down arrow
    map[0x7E] = "\u{2191}" // up arrow
    return map
}()

/// Convert a user-typed string to a key code. Accepts:
/// - Single character like "2", "a", "/"
/// - Hex key code like "0x15"
/// - Special names like "space", "return", "f1"
private func parseKeyInput(_ input: String) -> UInt16? {
    let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
    if trimmed.isEmpty { return nil }

    // Hex code
    if trimmed.hasPrefix("0x") {
        return UInt16(trimmed.dropFirst(2), radix: 16)
    }

    // Single character
    if trimmed.count == 1, let char = trimmed.first, let code = characterToKeyCode[char] {
        return code
    }

    // Special key names
    let specialNames: [String: UInt16] = [
        "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31,
        "delete": 0x33, "escape": 0x35, "esc": 0x35,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
    if let code = specialNames[trimmed] { return code }

    // Try as decimal number (raw key code)
    if let code = UInt16(trimmed) { return code }

    return nil
}

/// Display string for a key code — shows the character, not the hex code.
private func displayForKeyCode(_ code: UInt16) -> String {
    if let char = keyCodeToCharacter[code] {
        return char
    }
    return String(format: "0x%02X", code)
}

private struct GestureActionPicker: View {
    let label: String
    @Binding var action: GestureAction

    @State private var actionType: ActionType = .none
    @State private var keyInputString = ""
    @State private var modShift = false
    @State private var modControl = false
    @State private var modOption = false
    @State private var modCommand = false
    @State private var shellCommand = ""
    @State private var resolvedKeyCode: UInt16? = nil

    private enum ActionType: String, CaseIterable {
        case none = "None"
        case toggleVisuals = "Toggle Visuals"
        case keyPress = "Key Press"
        case shellCommand = "Shell Command"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Picker("", selection: $actionType) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .onChange(of: actionType) { _, _ in syncToAction() }
            }

            if actionType == .keyPress {
                HStack(spacing: 4) {
                    Toggle("\u{21E7}", isOn: $modShift).toggleStyle(.button).controlSize(.mini)
                        .onChange(of: modShift) { _, _ in syncToAction() }
                    Toggle("\u{2303}", isOn: $modControl).toggleStyle(.button).controlSize(.mini)
                        .onChange(of: modControl) { _, _ in syncToAction() }
                    Toggle("\u{2325}", isOn: $modOption).toggleStyle(.button).controlSize(.mini)
                        .onChange(of: modOption) { _, _ in syncToAction() }
                    Toggle("\u{2318}", isOn: $modCommand).toggleStyle(.button).controlSize(.mini)
                        .onChange(of: modCommand) { _, _ in syncToAction() }
                    TextField("Key", text: $keyInputString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 50)
                        .onChange(of: keyInputString) { _, _ in syncToAction() }
                }
                if let code = resolvedKeyCode {
                    Text("\u{2318}\(displayForKeyCode(code))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if !keyInputString.isEmpty {
                    Text("Unknown key")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }
            }

            if actionType == .shellCommand {
                TextField("Command", text: $shellCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                    .onChange(of: shellCommand) { _, _ in syncToAction() }
            }
        }
        .onAppear { syncFromAction() }
    }

    private func syncFromAction() {
        switch action {
        case .none:
            actionType = .none
        case .toggleVisuals:
            actionType = .toggleVisuals
        case .simulateKeyPress(let keyCode, let modifiers):
            actionType = .keyPress
            keyInputString = displayForKeyCode(keyCode)
            resolvedKeyCode = keyCode
            modShift = modifiers.contains(.shift)
            modControl = modifiers.contains(.control)
            modOption = modifiers.contains(.option)
            modCommand = modifiers.contains(.command)
        case .runShellCommand(let command):
            actionType = .shellCommand
            shellCommand = command
        }
    }

    private func syncToAction() {
        switch actionType {
        case .none:
            action = .none
        case .toggleVisuals:
            action = .toggleVisuals
        case .keyPress:
            let code = parseKeyInput(keyInputString)
            resolvedKeyCode = code
            var mods: [GestureModifierKey] = []
            if modShift { mods.append(.shift) }
            if modControl { mods.append(.control) }
            if modOption { mods.append(.option) }
            if modCommand { mods.append(.command) }
            action = .simulateKeyPress(keyCode: code ?? 0, modifiers: mods)
        case .shellCommand:
            action = .runShellCommand(command: shellCommand)
        }
    }
}
