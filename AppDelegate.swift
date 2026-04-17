import Cocoa
import SwiftUI

/// Fixed constants for the spring-based cursor follower.
enum SpringCursorConfig {
    static let response: CGFloat = 16.0
    static let dampingRatio: CGFloat = 1.08
    static let maxStep: TimeInterval = 1.0 / 240.0
    static let snapDistance: CGFloat = 240.0
    static let snapInterval: TimeInterval = 0.15
}

/// Fixed constants for smooth-mode delayed playback.
enum SmoothPlaybackConfig {
    /// Keep the trail slightly behind the real cursor so we can shape it with future samples.
    static let delay: TimeInterval = 0.075
    /// Emit synthetic trail points at a higher rate than incoming mouse events.
    static let sampleInterval: TimeInterval = 1.0 / 240.0
    /// Keep enough history to interpolate and fade the trail without unbounded growth.
    static let sampleHistoryDuration: TimeInterval = 1.5
}

/**
 * AppDelegate - Main application controller
 *
 * Manages the application lifecycle, creates trail overlay windows,
 * handles global event monitoring, and coordinates all UI updates.
 */
class AppDelegate: NSObject, NSApplicationDelegate {
    /**
     * Application constants organized in a nested enum for clarity
     * These values control the appearance and behavior of the app
     */
    // MARK: - Event Monitoring Properties

    /// Global event monitor registry; tears down on deinit.
    let eventMonitorHub = EventMonitorHub()

    /// Fallback timer if display-linked updates are unavailable
    var updateTimer: Timer?

    /// Display-linked animation driver for smooth refresh-synchronized updates
    var displayLink: CADisplayLink?

    // MARK: - Menu Bar Properties

    /// Trail settings (shared with SwiftUI MenuBarExtra)
    let settings = TrailSettings()

    /// Live info model (shared with SwiftUI MenuBarExtra)
    let liveInfo = LiveInfoModel()

    /// Preset manager (shared with SwiftUI MenuBarExtra)
    let presetManager = PresetManager()

    /// Timer for pushing live data to SwiftUI at 4Hz
    var infoUpdateTimer: Timer?

    /// Toggle states for windows
    var isTrailVisible = true
    var isRippleEnabled = false

    // MARK: - Trail Animation Properties

    /// Windows containing the trail (one per screen)
    var trailWindows: [NSPanel] = []

    /// The trail views (one per screen)
    var trailViews: [TrailView] = []

    // MARK: - Ripple Effect Properties

    /// Manager for ripple effects
    var rippleManager: RippleManager?

    // MARK: - Gesture Detection Properties

    /// Detector for mouse shake gestures
    var shakeDetector = ShakeDetector()

    /// Detector for circular mouse gestures
    var circleGestureDetector = CircleGestureDetector()

    /// Routes gesture events to configured actions
    var gestureRouter: GestureRouter = {
        let config = loadGestureConfig()
        return GestureRouter(shakeZones: config.shakeZones, circleConfig: config.circleConfig)
    }()

    /// Whether a circle gesture was detected while hyperkey was held, pending release to fire
    var hyperCirclePending = false

    /// Pending circle event for hyper+circle (needs direction info for routing on release)
    var pendingCircleEvent: CircleEvent? = nil

    /// Whether visuals are currently suppressed by a shake gesture (ephemeral, not persisted)
    var isShakeSuppressed = false

    /// Active calibration session (nil when not calibrating)
    var calibrationSession: CalibrationSession? = nil

    // MARK: - Performance Optimization Properties

    /// Motion state for adaptive performance
    enum MotionState {
        case idle
        case active
    }

    /// Click-drag classification state for left mouse button
    enum ClickDragState {
        case idle
        case pendingClassification(downLocation: NSPoint, downTimestamp: TimeInterval)
        case dragging
    }

    /// Current motion state
    var motionState: MotionState = .idle

    /// Current click-drag state (left button only)
    var clickDragState: ClickDragState = .idle

    /// Distance threshold (points) before classifying as drag
    let clickDragDistanceThreshold: CGFloat = 5.0

    /// Currently active algorithm backing the trail runtime.
    var activeTrailAlgorithm: TrailAlgorithm?

    /// Last mouse movement timestamp
    var lastMouseMovement: TimeInterval = 0

    /// State for the literal spring-based follower.
    var springCursorState: SpringCursorState?

    let springCursorResponse: CGFloat = SpringCursorConfig.response
    let springCursorDampingRatio: CGFloat = SpringCursorConfig.dampingRatio
    let springCursorMaxStep: TimeInterval = SpringCursorConfig.maxStep
    let springCursorSnapDistance: CGFloat = SpringCursorConfig.snapDistance
    let springCursorSnapInterval: TimeInterval = SpringCursorConfig.snapInterval

    /// Raw cursor samples used for delayed, spline-based trail playback.
    var rawMouseSamples: [MouseSample] = []

    /// Monotonic search cursor for the linear smooth-playback experiment.
    var smoothPlaybackSearchIndex = 0

    /// Playback cursor position in the raw-sample timeline.
    var visualPlaybackTime: TimeInterval?

    let visualPlaybackDelay: TimeInterval = SmoothPlaybackConfig.delay
    let visualPlaybackSampleInterval: TimeInterval = SmoothPlaybackConfig.sampleInterval
    let rawMouseSampleHistoryDuration: TimeInterval = SmoothPlaybackConfig.sampleHistoryDuration

    /// Idle timeout in seconds
    let idleTimeout: TimeInterval = 0.1

    /// Cached frontmost application
    var cachedFrontmostApp: String = "Unknown"


    /// Latest mouse location received from the global monitor
    var latestMouseLocation: NSPoint = .zero

    /// Pending mouse samples waiting to be drained on the next display tick
    var pendingMouseSamples: [MouseSample] = []
    let maxPendingMouseSamples = 256

    /// Trail views that received content recently and still need rendering.
    var dirtyTrailViewIndices: Set<Int> = []

    /// Timestamp of the last trail path rebuild.
    var lastTrailRenderTime: TimeInterval = 0

    private var performanceExperimentConfig: PerformanceExperimentConfig {
        PerformanceExperimentConfig(settings: settings)
    }

    private func ensureRippleManager() -> RippleManager {
        if let rippleManager {
            return rippleManager
        }

        let manager = RippleManager()
        manager.settings = settings
        manager.onRippleAdded = { [weak self] in
            guard let self else { return }
            // Restart animation driver if idle — the async capture may have
            // finished after the idle timeout stopped the driver.
            self.lastMouseMovement = currentMonotonicTime()
            if self.motionState == .idle {
                self.transitionToActiveState()
            }
        }
        rippleManager = manager
        return manager
    }

    private func applyCurrentTrailConfiguration(to trailView: TrailView) {
        let experiments = performanceExperimentConfig
        trailView.maxWidth = CGFloat(settings.maxWidth)
        trailView.movementThreshold = CGFloat(settings.movementThreshold)
        trailView.minimumVelocity = CGFloat(settings.minimumVelocity)
        trailView.maxPoints = experiments.trailMaxPoints
        trailView.minimumPointDistance = experiments.trailMinimumPointDistance
        trailView.maximumRenderSegmentLength = experiments.trailMaximumRenderSegmentLength
        trailView.renderSmoothingPasses = experiments.trailRenderSmoothingPasses
        trailView.glowWidthMultiplier = CGFloat(settings.glowWidthMultiplier)
        trailView.glowOuterOpacity = CGFloat(settings.glowOuterOpacity)
        trailView.glowMiddleOpacity = CGFloat(settings.glowMiddleOpacity)
        trailView.fadeTime = settings.coreFadeTime
        trailView.glowFadeTime = settings.glowFadeTime
        trailView.coreColor = settings.coreTrailNSColor
        trailView.glowColor = settings.glowTrailNSColor
        trailView.usesReducedLayerStack = experiments.useReducedLayerStack
        trailView.isCrosshairVisible = settings.isCrosshairVisible
        trailView.applyCrosshairStyle(
            color: settings.crosshairNSColor,
            lineWidth: CGFloat(settings.crosshairLineWidth)
        )
        trailView.updateLayerProperties()
    }

    private func handleTrailSettingsChanged() {
        applySettingsToTrailViews()
        smoothPlaybackSearchIndex = 0
        markVisibleTrailViewsDirty(at: currentMonotonicTime())

        if activeTrailAlgorithm != settings.trailAlgorithm {
            synchronizeTrailRuntime(clearTrail: true)
        } else {
            updateMouseCoalescingMode(for: settings.trailAlgorithm)
        }
    }

    private func updateMouseCoalescingMode(for algorithm: TrailAlgorithm) {
        NSEvent.isMouseCoalescingEnabled = performanceExperimentConfig.mouseCoalescingEnabled(for: algorithm)
    }

    private func resetTrailRuntimeState(
        to algorithm: TrailAlgorithm,
        at timestamp: TimeInterval,
        clearTrail: Bool
    ) {
        pendingMouseSamples.removeAll(keepingCapacity: true)
        springCursorState = nil
        rawMouseSamples.removeAll()
        smoothPlaybackSearchIndex = 0
        visualPlaybackTime = nil
        dirtyTrailViewIndices.removeAll()
        lastTrailRenderTime = 0
        activeTrailAlgorithm = algorithm
        updateMouseCoalescingMode(for: algorithm)

        if clearTrail {
            for trailView in trailViews {
                trailView.resetTrail()
            }
        } else {
            markVisibleTrailViewsDirty(at: timestamp)
        }

        switch algorithm {
        case .spring:
            resetSpringTrail(to: latestMouseLocation, timestamp: timestamp)
        case .smooth:
            resetVisualPlayback(to: latestMouseLocation, timestamp: timestamp)
        }
    }

    private func markVisibleTrailViewsDirty(at now: TimeInterval = currentMonotonicTime()) {
        for (index, trailView) in trailViews.enumerated() where trailView.hasVisiblePoints(at: now) {
            dirtyTrailViewIndices.insert(index)
        }
    }

    private func synchronizeTrailRuntime(clearTrail: Bool) {
        let now = currentMonotonicTime()
        latestMouseLocation = NSEvent.mouseLocation
        lastMouseMovement = now
        resetTrailRuntimeState(to: settings.trailAlgorithm, at: now, clearTrail: clearTrail)

        if motionState == .active {
            switch activeTrailAlgorithm ?? settings.trailAlgorithm {
            case .spring:
                advanceSpringTrail(toward: latestMouseLocation, timestamp: now)
            case .smooth:
                emitDelayedTrailPoints(upTo: now)
            }
            updateTrailAnimation(at: now)
        }
    }

    private func pointDistance(_ lhs: NSPoint, _ rhs: NSPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }

    private func interpolate(_ start: NSPoint, _ end: NSPoint, factor: CGFloat) -> NSPoint {
        NSPoint(
            x: start.x + ((end.x - start.x) * factor),
            y: start.y + ((end.y - start.y) * factor)
        )
    }

    private func extrapolatedEndpoint(from point: NSPoint, toward neighbor: NSPoint) -> NSPoint {
        NSPoint(
            x: point.x + (point.x - neighbor.x),
            y: point.y + (point.y - neighbor.y)
        )
    }

    private func resetSpringTrail(to location: NSPoint, timestamp: TimeInterval) {
        springCursorState = SpringCursorState(
            position: location,
            velocity: .zero,
            timestamp: timestamp
        )
    }

    private func integrateSpringTrail(
        _ state: inout SpringCursorState,
        toward target: NSPoint,
        deltaTime: TimeInterval
    ) {
        let dt = CGFloat(deltaTime)
        guard dt > 0 else { return }

        let stiffness = springCursorResponse * springCursorResponse
        let damping = 2 * springCursorDampingRatio * springCursorResponse

        let accelerationX = ((target.x - state.position.x) * stiffness) - (state.velocity.dx * damping)
        let accelerationY = ((target.y - state.position.y) * stiffness) - (state.velocity.dy * damping)

        state.velocity.dx += accelerationX * dt
        state.velocity.dy += accelerationY * dt
        state.position.x += state.velocity.dx * dt
        state.position.y += state.velocity.dy * dt
    }

    private func advanceSpringTrail(toward target: NSPoint, timestamp: TimeInterval) {
        guard var springCursorState else {
            resetSpringTrail(to: target, timestamp: timestamp)
            return
        }

        let deltaTime = max(timestamp - springCursorState.timestamp, 0)
        let distanceToTarget = pointDistance(springCursorState.position, target)

        if deltaTime <= 0 {
            return
        }

        if deltaTime > springCursorSnapInterval || distanceToTarget > springCursorSnapDistance {
            resetSpringTrail(to: target, timestamp: timestamp)
            return
        }

        let maxStep = min(springCursorMaxStep, performanceExperimentConfig.syntheticSampleInterval)
        let stepCount = max(1, Int(ceil(deltaTime / maxStep)))
        let stepDuration = deltaTime / Double(stepCount)

        for _ in 0..<stepCount {
            integrateSpringTrail(&springCursorState, toward: target, deltaTime: stepDuration)
            springCursorState.timestamp += stepDuration
            updateTrailPosition(at: springCursorState.position, timestamp: springCursorState.timestamp)
        }

        self.springCursorState = springCursorState
    }

    private func uniformCatmullRomPoint(
        _ p0: NSPoint,
        _ p1: NSPoint,
        _ p2: NSPoint,
        _ p3: NSPoint,
        t: CGFloat
    ) -> NSPoint {
        let t2 = t * t
        let t3 = t2 * t

        let x = 0.5 * (
            (2.0 * p1.x) +
            (-p0.x + p2.x) * t +
            ((2.0 * p0.x) - (5.0 * p1.x) + (4.0 * p2.x) - p3.x) * t2 +
            (-p0.x + (3.0 * p1.x) - (3.0 * p2.x) + p3.x) * t3
        )

        let y = 0.5 * (
            (2.0 * p1.y) +
            (-p0.y + p2.y) * t +
            ((2.0 * p0.y) - (5.0 * p1.y) + (4.0 * p2.y) - p3.y) * t2 +
            (-p0.y + (3.0 * p1.y) - (3.0 * p2.y) + p3.y) * t3
        )

        return NSPoint(x: x, y: y)
    }

    private func resetVisualPlayback(to location: NSPoint, timestamp: TimeInterval) {
        rawMouseSamples = [MouseSample(location: location, timestamp: timestamp)]
        smoothPlaybackSearchIndex = 0
        visualPlaybackTime = timestamp
    }

    private func appendRawMouseSample(_ sample: MouseSample) {
        if let lastSample = rawMouseSamples.last {
            if sample.timestamp <= lastSample.timestamp {
                rawMouseSamples[rawMouseSamples.count - 1] = sample
                return
            }

            if pointDistance(lastSample.location, sample.location) < 0.01 {
                rawMouseSamples[rawMouseSamples.count - 1] = sample
                return
            }
        }

        rawMouseSamples.append(sample)
    }

    private func interpolatedRawMouseLocation(at playbackTime: TimeInterval) -> NSPoint? {
        guard !rawMouseSamples.isEmpty else { return nil }

        if playbackTime <= rawMouseSamples[0].timestamp {
            return rawMouseSamples[0].location
        }

        guard let lastSample = rawMouseSamples.last else { return nil }
        if playbackTime >= lastSample.timestamp {
            return lastSample.location
        }

        if performanceExperimentConfig.useLinearSmoothPlaybackLookup {
            let upperBound = rawMouseSamples.count - 1
            smoothPlaybackSearchIndex = min(smoothPlaybackSearchIndex, max(upperBound - 1, 0))

            while smoothPlaybackSearchIndex > 0,
                  playbackTime < rawMouseSamples[smoothPlaybackSearchIndex].timestamp {
                smoothPlaybackSearchIndex -= 1
            }

            while smoothPlaybackSearchIndex < upperBound - 1,
                  playbackTime > rawMouseSamples[smoothPlaybackSearchIndex + 1].timestamp {
                smoothPlaybackSearchIndex += 1
            }

            return interpolatedRawMouseLocation(
                at: playbackTime,
                segmentIndex: smoothPlaybackSearchIndex
            )
        }

        for index in 0..<(rawMouseSamples.count - 1) {
            if let location = interpolatedRawMouseLocation(at: playbackTime, segmentIndex: index) {
                return location
            }
        }

        return lastSample.location
    }

    private func interpolatedRawMouseLocation(at playbackTime: TimeInterval, segmentIndex index: Int) -> NSPoint? {
        guard index >= 0, index + 1 < rawMouseSamples.count else { return nil }

        let startSample = rawMouseSamples[index]
        let endSample = rawMouseSamples[index + 1]

        guard playbackTime >= startSample.timestamp, playbackTime <= endSample.timestamp else {
            return nil
        }

        let duration = max(endSample.timestamp - startSample.timestamp, 0.0001)
        let t = CGFloat((playbackTime - startSample.timestamp) / duration)
        let p1 = startSample.location
        let p2 = endSample.location
        let p0 = index > 0
            ? rawMouseSamples[index - 1].location
            : extrapolatedEndpoint(from: p1, toward: p2)
        let p3 = (index + 2 < rawMouseSamples.count)
            ? rawMouseSamples[index + 2].location
            : extrapolatedEndpoint(from: p2, toward: p1)

        return uniformCatmullRomPoint(p0, p1, p2, p3, t: t)
    }

    private func pruneRawMouseSamples(relativeTo now: TimeInterval) {
        let cutoff = now - rawMouseSampleHistoryDuration
        guard rawMouseSamples.count > 2 else { return }

        var pruneCount = 0
        while pruneCount + 1 < rawMouseSamples.count,
              rawMouseSamples[pruneCount + 1].timestamp < cutoff {
            pruneCount += 1
        }

        guard pruneCount > 0 else { return }
        rawMouseSamples.removeFirst(pruneCount)
        if performanceExperimentConfig.useLinearSmoothPlaybackLookup {
            smoothPlaybackSearchIndex = max(0, smoothPlaybackSearchIndex - pruneCount)
        }
    }

    private func emitDelayedTrailPoints(upTo now: TimeInterval) {
        guard rawMouseSamples.count >= 2 else { return }

        let playbackEnd = min(now - visualPlaybackDelay, rawMouseSamples[rawMouseSamples.count - 1].timestamp)
        guard playbackEnd.isFinite else { return }

        if visualPlaybackTime == nil {
            visualPlaybackTime = rawMouseSamples[0].timestamp
        }

        guard let startPlaybackTime = visualPlaybackTime, playbackEnd > startPlaybackTime else {
            return
        }

        let sampleInterval = performanceExperimentConfig.syntheticSampleInterval
        var playbackTime = startPlaybackTime
        while playbackTime < playbackEnd {
            playbackTime = min(playbackTime + sampleInterval, playbackEnd)

            if let location = interpolatedRawMouseLocation(at: playbackTime) {
                updateTrailPosition(at: location, timestamp: playbackTime + visualPlaybackDelay)
            }
        }

        visualPlaybackTime = playbackEnd
        pruneRawMouseSamples(relativeTo: now)
    }

    private func enqueueMouseSample(location: NSPoint, timestamp: TimeInterval) {
        latestMouseLocation = location
        pendingMouseSamples.append(MouseSample(location: location, timestamp: timestamp))

        if pendingMouseSamples.count > maxPendingMouseSamples {
            pendingMouseSamples.removeFirst(pendingMouseSamples.count - maxPendingMouseSamples)
        }
    }

    private func drainPendingMouseSamples() {
        guard !pendingMouseSamples.isEmpty else { return }

        let samples = pendingMouseSamples
        pendingMouseSamples.removeAll(keepingCapacity: true)

        for sample in samples {
            switch activeTrailAlgorithm ?? settings.trailAlgorithm {
            case .spring:
                advanceSpringTrail(toward: sample.location, timestamp: sample.timestamp)
            case .smooth:
                appendRawMouseSample(sample)
            }
        }
    }

    private func updateTrailAnimation(at now: TimeInterval) {
        let experiments = performanceExperimentConfig
        let minimumRenderInterval = experiments.trailRenderMinimumInterval
        if minimumRenderInterval > 0,
           lastTrailRenderTime > 0,
           now - lastTrailRenderTime < minimumRenderInterval {
            return
        }

        lastTrailRenderTime = now

        if experiments.onlyUpdateDirtyScreens {
            if dirtyTrailViewIndices.isEmpty {
                markVisibleTrailViewsDirty(at: now)
            }

            var nextDirtyIndices: Set<Int> = []
            for index in dirtyTrailViewIndices where index < trailViews.count {
                let trailView = trailViews[index]
                trailView.updateTrail(at: now)
                if trailView.hasVisiblePoints(at: now) {
                    nextDirtyIndices.insert(index)
                }
            }

            dirtyTrailViewIndices = nextDirtyIndices
            return
        }

        for trailView in trailViews {
            trailView.updateTrail(at: now)
        }
    }

    // MARK: - Live Info Updates for Menu Bar

    func startInfoUpdates() {
        guard infoUpdateTimer == nil else { return }
        pushLiveInfoToModel()
        infoUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pushLiveInfoToModel()
        }
    }

    func stopInfoUpdates() {
        infoUpdateTimer?.invalidate()
        infoUpdateTimer = nil
    }

    private func pushLiveInfoToModel() {
        liveInfo.mouseX = Int(latestMouseLocation.x)
        liveInfo.mouseY = Int(latestMouseLocation.y)
        liveInfo.frontmostApp = cachedFrontmostApp
        liveInfo.screenRecordingGranted = rippleManager?.hasPermission ?? false
        liveInfo.accessibilityGranted = AXIsProcessTrusted()
        let screens = NSScreen.screens
        liveInfo.screenCount = screens.count
        liveInfo.screenDescriptions = screens.enumerated().map { (i, s) in
            let isMain = s == NSScreen.main ? " (main)" : ""
            return "[\(i+1)] \(Int(s.frame.width))×\(Int(s.frame.height))\(isMain)"
        }
    }

    // MARK: - Help Window

    var helpWindow: NSWindow?

    func showHelpWindow() {
        if let existing = helpWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: HelpView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MouseTrail README"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        helpWindow = window
    }

    func requestScreenRecordingPermission() {
        logInfo("Manual permission request triggered")

        let currentStatus = CGPreflightScreenCaptureAccess()
        logInfo("Current permission status: \(currentStatus)")

        let rippleManager = ensureRippleManager()
        rippleManager.checkAndSetupScreenCapture()

        if !currentStatus {
            CGRequestScreenCaptureAccess()
            logInfo("Permission requested, opening System Settings")

            let urls = [
                "x-apple.systempreferences:com.apple.Privacy-ScreenRecording",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security"
            ]

            var opened = false
            for urlString in urls {
                if let url = URL(string: urlString) {
                    if NSWorkspace.shared.open(url) {
                        debugLog("Opened System Settings with URL: \(urlString)")
                        opened = true
                        break
                    }
                }
            }

            if !opened {
                debugLog("Failed to open System Settings to Screen Recording section")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                debugLog("Re-checking permission after manual request")
                self?.rippleManager?.checkAndSetupScreenCapture()
            }
        }
    }

    func requestAccessibilityPermission() {
        logInfo("Accessibility permission request triggered")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        logInfo("Accessibility trusted: \(granted)")

        if !granted {
            let urls = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                "x-apple.systempreferences:com.apple.preference.security"
            ]
            for urlString in urls {
                if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                    debugLog("Opened System Settings with URL: \(urlString)")
                    break
                }
            }
        }
    }

    private func installEventMonitors() {
        // Monitor mouse movement, including drag events so the trail stays continuous.
        let movementMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]
        eventMonitorHub.addGlobal(for: movementMask) { [weak self] event in
            self?.handleMouseMovement(event)
        }
        eventMonitorHub.addGlobal(for: .leftMouseDown) { [weak self] event in
            self?.handleMouseClick(event)
        }
        eventMonitorHub.addGlobal(for: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
        }
        eventMonitorHub.addGlobal(for: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        // NOTE: local monitors intentionally omitted — the app has no key window in
        // normal use (LSUIElement menu bar app), so local monitors would only fire
        // when the settings/help window is keyed, and they'd double-feed gesture
        // detectors when they do. Global monitor alone covers our needs.
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogFileViewer.shared.start()
        logInfo("MouseTrail starting...")

        guard NSScreen.screens.first != nil else {
            logInfo("No screens available")
            NSApplication.shared.terminate(self)
            return
        }

        latestMouseLocation = NSEvent.mouseLocation
        let launchTimestamp = currentMonotonicTime()
        lastMouseMovement = launchTimestamp

        // Wire settings callbacks
        settings.restore()
        presetManager.takeCleanSnapshot(from: settings)
        isTrailVisible = settings.isTrailVisible
        isRippleEnabled = settings.isRippleEnabled
        settings.onChange = { [weak self] delta in
            guard let self else { return }
            switch delta {
            case .appearance:
                self.handleTrailSettingsChanged()
            case .visibility:
                self.applyVisibilitySettings()
            case .gesture:
                self.applyGestureDetectorParams()
            }
        }
        applyGestureDetectorParams()

        // Create trail windows for each screen
        createTrailWindows()
        handleTrailSettingsChanged()

        logInfo("MouseTrail initialized successfully")
        logInfo("Trail windows created: \(trailWindows.count)")
        logInfo("Monitoring mouse events...")

        // Cache initial system state
        updateCachedSystemInfo()
        installEventMonitors()

        // Monitor app switching
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Monitor screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /**
     * Handles left mouse down: begins click-drag classification.
     * Ripple is deferred to mouseUp so drags don't trigger it.
     */
    func handleMouseClick(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let timestamp = currentMonotonicTime()

        // Safety: if previous gesture wasn't cleaned up, reset
        switch clickDragState {
        case .idle: break
        default: clickDragState = .idle
        }

        clickDragState = .pendingClassification(downLocation: location, downTimestamp: timestamp)

        // Keep animation driver alive
        lastMouseMovement = timestamp
        if motionState == .idle {
            transitionToActiveState()
        }
    }

    /**
     * Handles left mouse up: fires ripple if it was a click, resets drag state.
     */
    func handleMouseUp(_ event: NSEvent) {
        switch clickDragState {
        case .pendingClassification(let downLocation, _):
            // Still pending = never exceeded drag threshold = it was a click
            if isRippleEnabled && !isShakeSuppressed {
                logInfo("Click detected, firing ripple at: \(downLocation)")
                lastMouseMovement = currentMonotonicTime()
                ensureRippleManager().createRipple(at: downLocation)
                if motionState == .idle {
                    transitionToActiveState()
                }
            }
        case .dragging:
            debugLog("Drag ended, no ripple")
        case .idle:
            break
        }
        clickDragState = .idle
    }

    /// All four modifier keys held simultaneously (Shift+Control+Option+Command).
    private static let hyperkeyModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// Fires the hyper+circle action when hyperkey is released after a circle gesture was detected.
    private func handleFlagsChanged(_ event: NSEvent) {
        if !event.modifierFlags.contains(Self.hyperkeyModifiers) {
            if hyperCirclePending, let circleEvent = pendingCircleEvent {
                hyperCirclePending = false
                pendingCircleEvent = nil
                let action = gestureRouter.action(for: circleEvent, isHyperPressed: true)
                logInfo("Hyper released with pending circle — executing: \(action.displayName)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.executeGestureAction(action)
                }
            }
        }
    }

    /**
     * Handles mouse movement events with motion detection
     */
    func handleMouseMovement(_ event: NSEvent) {
        let timestamp = currentMonotonicTime()

        // Suppress trail during left-click drags
        if event.type == .leftMouseDragged {
            switch clickDragState {
            case .pendingClassification(let downLocation, _):
                let currentLocation = NSEvent.mouseLocation
                let distance = pointDistance(currentLocation, downLocation)
                if distance > clickDragDistanceThreshold {
                    clickDragState = .dragging
                    debugLog("Classified as drag (distance: \(distance))")
                }
                // Suppress trail during pending period for left-drag events
                lastMouseMovement = timestamp
                latestMouseLocation = NSEvent.mouseLocation
                return
            case .dragging:
                // Keep animation driver alive but suppress trail
                lastMouseMovement = timestamp
                latestMouseLocation = NSEvent.mouseLocation
                return
            case .idle:
                break
            }
        }

        let sample = MouseSample(location: NSEvent.mouseLocation, timestamp: timestamp)
        lastMouseMovement = sample.timestamp
        enqueueMouseSample(location: sample.location, timestamp: sample.timestamp)

        // Feed calibration session if active
        _ = calibrationSession?.addSample(sample)

        // Check for shake gesture
        if let shakeEvent = shakeDetector.addSample(sample) {
            handleShakeDetected(shakeEvent)
        }

        // Check for circle gesture
        if let circleEvent = circleGestureDetector.addSample(sample) {
            logInfo("Circle detected: \(circleEvent.direction.rawValue) radius=\(String(format: "%.0f", circleEvent.averageRadius)) circles=\(circleEvent.circleCount)")
            if event.modifierFlags.contains(Self.hyperkeyModifiers) {
                hyperCirclePending = true
                pendingCircleEvent = circleEvent
                logInfo("Hyper+circle gesture detected, pending hyper release")
            } else {
                let action = gestureRouter.action(for: circleEvent, isHyperPressed: false)
                executeGestureAction(action)
            }
        }

        // Transition to active state if we were idle
        if motionState == .idle {
            resetTrailRuntimeState(to: settings.trailAlgorithm, at: sample.timestamp, clearTrail: false)
            transitionToActiveState()
            drainPendingMouseSamples()
            switch activeTrailAlgorithm ?? settings.trailAlgorithm {
            case .spring:
                advanceSpringTrail(toward: latestMouseLocation, timestamp: currentMonotonicTime())
            case .smooth:
                emitDelayedTrailPoints(upTo: currentMonotonicTime())
            }
            updateTrailAnimation(at: currentMonotonicTime())
        }
    }

    /**
     * Transition from idle to active state
     */
    func transitionToActiveState() {
        guard motionState == .idle else { return }
        motionState = .active

        // Start display link for vsync-synchronized updates
        setupDisplayLink()
    }

    /**
     * Sets up a refresh-synchronized display link for smooth animation.
     */
    func setupDisplayLink() {
        stopAnimationDriver()

        if #available(macOS 14.0, *), let displayWindow = trailWindows.first, displayWindow.isVisible {
            let link = displayWindow.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
            return
        }

        logInfo("Falling back to 60Hz timer because AppKit display links are unavailable")
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateActiveAnimation()
        }

        if let timer = updateTimer {
            timer.tolerance = 1.0 / 120.0  // half a frame at 60Hz — lets the OS batch wakeups
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        updateActiveAnimation()
    }

    private func stopAnimationDriver() {
        updateTimer?.invalidate()
        updateTimer = nil

        displayLink?.invalidate()
        displayLink = nil
        lastTrailRenderTime = 0
    }

    // MARK: - Shake Detection

    func handleShakeDetected(_ event: ShakeEvent) {
        guard settings.isShakeToggleEnabled else { return }
        let angleDegrees = event.axisAngle * 180 / .pi
        logInfo("Shake detected: axis=\(String(format: "%.0f", angleDegrees))° reversals=\(event.reversals) velocity=\(String(format: "%.0f", event.averageVelocity)) spread=\(String(format: "%.1f", event.angularSpread * 180 / .pi))°")

        guard let zone = gestureRouter.matchingZone(for: event) else {
            logDebug("Shake at \(String(format: "%.0f", angleDegrees))° matched no zone")
            return
        }
        logInfo("Shake matched zone: \(zone.name)")
        executeGestureAction(zone.action)
    }

    /// Apply gesture detector parameters from settings to the live detector instances.
    func applyGestureDetectorParams() {
        shakeDetector.timeWindow = settings.shakeTimeWindow
        shakeDetector.requiredReversals = settings.shakeRequiredReversals
        shakeDetector.minimumSegmentDisplacement = CGFloat(settings.shakeMinDisplacement)
        shakeDetector.minimumSegmentVelocity = CGFloat(settings.shakeMinVelocity)
        shakeDetector.cooldownDuration = settings.shakeCooldown
        shakeDetector.maximumAngularDeviation = CGFloat(settings.shakeAngularTolerance) * .pi / 180

        circleGestureDetector.circleTimeWindow = settings.circleTimeWindow
        circleGestureDetector.sampleWindow = settings.circleSampleWindow
        circleGestureDetector.minimumRadius = CGFloat(settings.circleMinRadius)
        circleGestureDetector.minimumSpeed = CGFloat(settings.circleMinSpeed)
        circleGestureDetector.cooldownDuration = settings.circleCooldown
        circleGestureDetector.requiredCircles = settings.circleRequiredCircles
        circleGestureDetector.maximumRadiusVariance = CGFloat(settings.circleMaxRadiusVariance)

        logDebug("Gesture detector params applied from settings")
    }

    /// Persist current gesture router configuration to UserDefaults.
    func saveGestureSettings() {
        saveGestureConfig(zones: gestureRouter.shakeZones, circleConfig: gestureRouter.circleConfig)
    }

    /// Execute a gesture action, handling both built-in and external actions.
    func executeGestureAction(_ action: GestureAction) {
        gestureRouter.execute(action) { [weak self] keyCode, modifiers in
            self?.simulateKeyPress(keyCode: keyCode, modifiers: modifiers)
        }
        // Handle built-in actions that need AppCore state
        if case .toggleVisuals = action {
            isShakeSuppressed.toggle()
            logInfo("Gesture toggle: visuals \(isShakeSuppressed ? "OFF" : "ON")")
            applyShakeSuppressionState()
        }
    }

    func applyShakeSuppressionState() {
        if isShakeSuppressed {
            // Hide everything without touching settings or cached state
            for trailView in trailViews {
                trailView.isCrosshairVisible = false
                trailView.clearCrosshair()
            }
            for trailWindow in trailWindows {
                trailWindow.orderOut(nil)
            }
            rippleManager?.clearAllRipples()
        } else {
            // Restore from actual settings
            applyVisibilitySettings()
        }
    }

    // MARK: - Simulated Key Events

    func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            logInfo("Failed to create CGEvent for key simulation")
            return
        }
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /**
     * Transition from active to idle state
     */
    func transitionToIdleState() {
        guard motionState == .active else { return }
        let now = currentMonotonicTime()

        // Check if trail still has visible points
        var hasVisibleTrail = false
        for trailView in trailViews {
            if trailView.hasVisiblePoints(at: now) {
                hasVisibleTrail = true
                break
            }
        }

        // Check if ripples are still active
        let hasActiveRipples = !(rippleManager?.activeRipples.isEmpty ?? true)

        if hasVisibleTrail || hasActiveRipples {
            return
        }

        // Trail is fully faded, safe to go idle
        motionState = .idle
        springCursorState = nil
        rawMouseSamples.removeAll()
        smoothPlaybackSearchIndex = 0
        visualPlaybackTime = nil
        pendingMouseSamples.removeAll(keepingCapacity: true)
        dirtyTrailViewIndices.removeAll()

        // Stop the animation driver to save CPU
        stopAnimationDriver()
    }

    /**
     * Update only during active animation (called by timer)
     */
    func updateActiveAnimation() {
        let now = currentMonotonicTime()
        drainPendingMouseSamples()
        switch activeTrailAlgorithm ?? settings.trailAlgorithm {
        case .spring:
            advanceSpringTrail(toward: latestMouseLocation, timestamp: now)
        case .smooth:
            emitDelayedTrailPoints(upTo: now)
        }
        updateTrailAnimation(at: now)

        rippleManager?.updateRipples()
        updateCrosshairs()

        if now - lastMouseMovement >= idleTimeout {
            transitionToIdleState()
        }
    }

    private func updateCrosshairs() {
        guard settings.isCrosshairVisible, !isShakeSuppressed else { return }
        let mouseLocation = latestMouseLocation

        for trailView in trailViews {
            guard let window = trailView.window else { continue }
            let screenFrame = window.frame

            if screenFrame.contains(mouseLocation) {
                let viewPoint = NSPoint(
                    x: mouseLocation.x - screenFrame.origin.x,
                    y: mouseLocation.y - screenFrame.origin.y
                )
                trailView.updateCrosshair(at: viewPoint)
            } else {
                trailView.clearCrosshair()
            }
        }
    }

    func updateCachedSystemInfo() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            cachedFrontmostApp = frontApp.localizedName ?? "Unknown"
        }
    }

    @objc func activeApplicationChanged(_ notification: Notification) {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            cachedFrontmostApp = frontApp.localizedName ?? "Unknown"
        }
    }

    @objc func screenConfigurationChanged(_ notification: Notification) {
        createTrailWindows()
        updateCachedSystemInfo()
        resetTrailRuntimeState(to: settings.trailAlgorithm, at: currentMonotonicTime(), clearTrail: false)
    }

    /// Apply current settings to all TrailView instances
    func applySettingsToTrailViews() {
        for trailView in trailViews {
            applyCurrentTrailConfiguration(to: trailView)
        }
    }

    /// Apply visibility toggle changes
    func applyVisibilitySettings() {
        // If the user explicitly changes a visibility setting, cancel shake suppression
        if isShakeSuppressed {
            isShakeSuppressed = false
            logInfo("Shake suppression cleared by settings change")
        }

        // Trail visibility
        if settings.isTrailVisible != isTrailVisible {
            isTrailVisible = settings.isTrailVisible
        }

        // Crosshair visibility
        for trailView in trailViews {
            trailView.isCrosshairVisible = settings.isCrosshairVisible
        }
        if !settings.isCrosshairVisible {
            for trailView in trailViews {
                trailView.clearCrosshair()
            }
        }

        // Show trail windows if either trail or crosshairs are enabled
        let shouldShowWindows = isTrailVisible || settings.isCrosshairVisible
        for trailWindow in trailWindows {
            if shouldShowWindows {
                trailWindow.orderFront(nil)
            } else {
                trailWindow.orderOut(nil)
            }
        }

        // If crosshairs just enabled, render immediately
        if settings.isCrosshairVisible {
            updateCrosshairs()
        }

        // Ripple effect
        if settings.isRippleEnabled != isRippleEnabled {
            isRippleEnabled = settings.isRippleEnabled
            if isRippleEnabled {
                _ = ensureRippleManager()
            } else {
                rippleManager?.clearAllRipples()
            }
        }
    }

    /**
     * Creates separate trail overlay windows for each screen
     *
     * Each window is configured to:
     * - Be completely click-through (no mouse interaction)
     * - Cover its specific screen
     * - Use hardware-accelerated rendering via CAShapeLayer
     * - Stay visible on all spaces and over full-screen apps
     */
    func createTrailWindows() {
        // Clear any existing windows
        for window in trailWindows {
            window.close()
        }
        trailWindows.removeAll()
        trailViews.removeAll()
        dirtyTrailViewIndices.removeAll()

        // Create a window for each screen
        for screen in NSScreen.screens {
            let screenFrame = screen.frame

            // Create window for this screen
            let trailWindow = NSPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            // Configure window for overlay behavior
            trailWindow.isOpaque = false                    // Allow transparency
            trailWindow.backgroundColor = .clear            // Clear background
            trailWindow.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)  // Above menu bar

            // Collection behaviors control how the window interacts with Spaces and Mission Control
            trailWindow.collectionBehavior = [
                .canJoinAllSpaces,                        // Visible on all spaces/desktops
                .fullScreenAuxiliary,                     // Visible over full-screen apps
                .transient,                               // Don't show in window list or App Exposé
                .ignoresCycle,                            // Don't participate in Cmd+Tab cycling
                .stationary                               // Don't move with spaces transitions
            ]
            trailWindow.hidesOnDeactivate = false          // Stay visible when app loses focus
            trailWindow.ignoresMouseEvents = true          // Click-through
            trailWindow.hasShadow = false                  // No window shadow
            trailWindow.isReleasedWhenClosed = false       // Don't release when closed

            // Create the trail view for this screen
            let viewBounds = NSRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
            let trailView = TrailView(frame: viewBounds)
            trailView.wantsLayer = true
            applyCurrentTrailConfiguration(to: trailView)

            trailWindow.contentView = trailView

            // Only show if trails or crosshairs are enabled
            if isTrailVisible || settings.isCrosshairVisible {
                trailWindow.orderFront(nil)
            }

            // Store references
            trailWindows.append(trailWindow)
            trailViews.append(trailView)
        }
    }

    /**
     * Updates the trail with the current mouse position
     *
     * This adds the current mouse position to the trail view that owns the point.
     */
    func updateTrailPosition(at screenLocation: NSPoint, timestamp: TimeInterval) {
        for (index, trailView) in trailViews.enumerated() {
            if trailView.addPoint(screenLocation, at: timestamp) {
                dirtyTrailViewIndices.insert(index)
                break
            }
        }
    }


    /**
     * Performs cleanup when the application is about to terminate
     *
     * This ensures all resources are properly released:
     * - Timers are invalidated to prevent retain cycles
     * - Event monitors are removed to stop receiving events
     * - Windows are closed
     * - Notification observers are removed
     *
     * While macOS would clean up most resources automatically, explicit cleanup
     * is good practice and prevents potential issues.
     */
    func applicationWillTerminate(_ notification: Notification) {
        settings.flushPendingSave()
        stopAnimationDriver()
        infoUpdateTimer?.invalidate()
        infoUpdateTimer = nil
        NSEvent.isMouseCoalescingEnabled = true

        eventMonitorHub.removeAll()

        for window in trailWindows {
            window.close()
        }
        trailWindows.removeAll()
        trailViews.removeAll()

        rippleManager?.cleanup()

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
