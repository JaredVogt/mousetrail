import Foundation
import AppKit
import SwiftUI

enum TrailAlgorithm: String, CaseIterable, Codable {
    case spring
    case smooth

    var displayName: String {
        switch self {
        case .spring: "Spring"
        case .smooth: "Smooth"
        }
    }
}

/// Single source of truth for `TrailSettings` default values.
enum TrailSettingsDefaults {
    // Visibility
    static let isTrailVisible = true
    static let isInfoPanelVisible = false
    static let isRippleEnabled = false
    static let isCrosshairVisible = false
    static let isShakeToggleEnabled = false
    static let logLevelRaw = 1

    // Shake detector
    static let shakeTimeWindow = 0.5
    static let shakeRequiredReversals = 3
    static let shakeMinDisplacement = 50.0
    static let shakeMinVelocity = 800.0
    static let shakeCooldown = 1.0
    static let shakeAngularTolerance = 45.0

    // Circle detector
    static let circleTimeWindow = 3.0
    static let circleSampleWindow = 1.5
    static let circleMinRadius = 30.0
    static let circleMinSpeed = 200.0
    static let circleCooldown = 2.0
    static let circleRequiredCircles = 2
    static let circleMaxRadiusVariance = 3.0

    // Trail appearance
    static let maxWidth = 8.0
    static let glowWidthMultiplier = 3.5
    static let trailAlgorithm: TrailAlgorithm = .smooth
    static let movementThreshold = 30.0
    static let minimumVelocity = 0.0
    static let coreFadeTime = 0.6
    static let glowFadeTime = 0.35

    // Core color
    static let coreTrailR = 1.0
    static let coreTrailG = 0.15
    static let coreTrailB = 0.1

    // Glow color
    static let glowTrailR = 0.1
    static let glowTrailG = 0.5
    static let glowTrailB = 1.0

    // Glow opacity
    static let glowOuterOpacity = 0.02
    static let glowMiddleOpacity = 0.08

    // Crosshair
    static let crosshairR = 1.0
    static let crosshairG = 1.0
    static let crosshairB = 1.0
    static let crosshairOpacity = 0.3
    static let crosshairLineWidth = 1.0

    // Ripple
    static let rippleRadius = 150.0
    static let rippleSpeed = 120.0
    static let rippleWavelength = 25.0
    static let rippleDamping = 2.0
    static let rippleAmplitude = 12.0
    static let rippleDuration = 1.2
    static let rippleSpecularIntensity = 0.8

    // Performance experiments
    static let reduceSyntheticSampleRate = false
    static let enableSmoothInputCoalescing = false
    static let useReducedLayerStack = false
    static let onlyUpdateDirtyScreens = false
    static let useLinearSmoothPlaybackLookup = false
    static let useStrongerPointDecimation = false
    static let useRelaxedPathRebuild = false
    static let capTrailRenderingTo60FPS = false
}

@Observable
class TrailSettings {
    /// Callback when trail appearance settings change
    var onChanged: (() -> Void)?
    /// Callback when visibility toggles change
    var onVisibilityChanged: (() -> Void)?

    // MARK: - Visibility

    var isTrailVisible = TrailSettingsDefaults.isTrailVisible { didSet { save(); onVisibilityChanged?() } }
    var isInfoPanelVisible = TrailSettingsDefaults.isInfoPanelVisible { didSet { save(); onVisibilityChanged?() } }
    var isRippleEnabled = TrailSettingsDefaults.isRippleEnabled { didSet { save(); onVisibilityChanged?() } }
    var isCrosshairVisible = TrailSettingsDefaults.isCrosshairVisible { didSet { save(); onVisibilityChanged?() } }
    var isShakeToggleEnabled = TrailSettingsDefaults.isShakeToggleEnabled { didSet { save() } }
    var logLevelRaw = TrailSettingsDefaults.logLevelRaw { didSet { save(); currentLogLevel = LogLevel(rawValue: logLevelRaw) ?? .info } }

    // MARK: - Shake Detector Parameters

    /// Callback when gesture detector parameters change
    var onGestureParamsChanged: (() -> Void)?

    var shakeTimeWindow = TrailSettingsDefaults.shakeTimeWindow { didSet { save(); onGestureParamsChanged?() } }
    var shakeRequiredReversals = TrailSettingsDefaults.shakeRequiredReversals { didSet { save(); onGestureParamsChanged?() } }
    var shakeMinDisplacement = TrailSettingsDefaults.shakeMinDisplacement { didSet { save(); onGestureParamsChanged?() } }
    var shakeMinVelocity = TrailSettingsDefaults.shakeMinVelocity { didSet { save(); onGestureParamsChanged?() } }
    var shakeCooldown = TrailSettingsDefaults.shakeCooldown { didSet { save(); onGestureParamsChanged?() } }
    var shakeAngularTolerance = TrailSettingsDefaults.shakeAngularTolerance { didSet { save(); onGestureParamsChanged?() } }

    // MARK: - Circle Detector Parameters

    var circleTimeWindow = TrailSettingsDefaults.circleTimeWindow { didSet { save(); onGestureParamsChanged?() } }
    var circleSampleWindow = TrailSettingsDefaults.circleSampleWindow { didSet { save(); onGestureParamsChanged?() } }
    var circleMinRadius = TrailSettingsDefaults.circleMinRadius { didSet { save(); onGestureParamsChanged?() } }
    var circleMinSpeed = TrailSettingsDefaults.circleMinSpeed { didSet { save(); onGestureParamsChanged?() } }
    var circleCooldown = TrailSettingsDefaults.circleCooldown { didSet { save(); onGestureParamsChanged?() } }
    var circleRequiredCircles = TrailSettingsDefaults.circleRequiredCircles { didSet { save(); onGestureParamsChanged?() } }
    var circleMaxRadiusVariance = TrailSettingsDefaults.circleMaxRadiusVariance { didSet { save(); onGestureParamsChanged?() } }

    // MARK: - Trail Width

    var maxWidth = TrailSettingsDefaults.maxWidth { didSet { save(); onChanged?() } }
    var glowWidthMultiplier = TrailSettingsDefaults.glowWidthMultiplier { didSet { save(); onChanged?() } }

    // MARK: - Trail Motion

    var trailAlgorithm: TrailAlgorithm = TrailSettingsDefaults.trailAlgorithm { didSet { save(); onChanged?() } }

    // MARK: - Movement

    var movementThreshold = TrailSettingsDefaults.movementThreshold { didSet { save(); onChanged?() } }
    var minimumVelocity = TrailSettingsDefaults.minimumVelocity { didSet { save(); onChanged?() } }

    // MARK: - Fade Duration

    var coreFadeTime = TrailSettingsDefaults.coreFadeTime { didSet { save(); onChanged?() } }
    var glowFadeTime = TrailSettingsDefaults.glowFadeTime { didSet { save(); onChanged?() } }

    // MARK: - Core Trail Color (RGB components)

    var coreTrailR = TrailSettingsDefaults.coreTrailR { didSet { save(); onChanged?() } }
    var coreTrailG = TrailSettingsDefaults.coreTrailG { didSet { save(); onChanged?() } }
    var coreTrailB = TrailSettingsDefaults.coreTrailB { didSet { save(); onChanged?() } }

    // MARK: - Glow Trail Color (RGB components)

    var glowTrailR = TrailSettingsDefaults.glowTrailR { didSet { save(); onChanged?() } }
    var glowTrailG = TrailSettingsDefaults.glowTrailG { didSet { save(); onChanged?() } }
    var glowTrailB = TrailSettingsDefaults.glowTrailB { didSet { save(); onChanged?() } }

    // MARK: - Glow Trail Opacity

    var glowOuterOpacity = TrailSettingsDefaults.glowOuterOpacity { didSet { save(); onChanged?() } }
    var glowMiddleOpacity = TrailSettingsDefaults.glowMiddleOpacity { didSet { save(); onChanged?() } }

    // MARK: - Crosshair Appearance

    var crosshairR = TrailSettingsDefaults.crosshairR { didSet { save(); onChanged?() } }
    var crosshairG = TrailSettingsDefaults.crosshairG { didSet { save(); onChanged?() } }
    var crosshairB = TrailSettingsDefaults.crosshairB { didSet { save(); onChanged?() } }
    var crosshairOpacity = TrailSettingsDefaults.crosshairOpacity { didSet { save(); onChanged?() } }
    var crosshairLineWidth = TrailSettingsDefaults.crosshairLineWidth { didSet { save(); onChanged?() } }

    // MARK: - Ripple Effect

    var rippleRadius = TrailSettingsDefaults.rippleRadius { didSet { save(); onChanged?() } }
    var rippleSpeed = TrailSettingsDefaults.rippleSpeed { didSet { save(); onChanged?() } }
    var rippleWavelength = TrailSettingsDefaults.rippleWavelength { didSet { save(); onChanged?() } }
    var rippleDamping = TrailSettingsDefaults.rippleDamping { didSet { save(); onChanged?() } }
    var rippleAmplitude = TrailSettingsDefaults.rippleAmplitude { didSet { save(); onChanged?() } }
    var rippleDuration = TrailSettingsDefaults.rippleDuration { didSet { save(); onChanged?() } }
    var rippleSpecularIntensity = TrailSettingsDefaults.rippleSpecularIntensity { didSet { save(); onChanged?() } }

    // MARK: - Performance Experiments

    var reduceSyntheticSampleRate = TrailSettingsDefaults.reduceSyntheticSampleRate { didSet { save(); onChanged?() } }
    var enableSmoothInputCoalescing = TrailSettingsDefaults.enableSmoothInputCoalescing { didSet { save(); onChanged?() } }
    var useReducedLayerStack = TrailSettingsDefaults.useReducedLayerStack { didSet { save(); onChanged?() } }
    var onlyUpdateDirtyScreens = TrailSettingsDefaults.onlyUpdateDirtyScreens { didSet { save(); onChanged?() } }
    var useLinearSmoothPlaybackLookup = TrailSettingsDefaults.useLinearSmoothPlaybackLookup { didSet { save(); onChanged?() } }
    var useStrongerPointDecimation = TrailSettingsDefaults.useStrongerPointDecimation { didSet { save(); onChanged?() } }
    var useRelaxedPathRebuild = TrailSettingsDefaults.useRelaxedPathRebuild { didSet { save(); onChanged?() } }
    var capTrailRenderingTo60FPS = TrailSettingsDefaults.capTrailRenderingTo60FPS { didSet { save(); onChanged?() } }

    // MARK: - Computed Colors

    var coreTrailColor: Color {
        get { Color(red: coreTrailR, green: coreTrailG, blue: coreTrailB) }
        set {
            guard let components = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            coreTrailR = components.redComponent
            coreTrailG = components.greenComponent
            coreTrailB = components.blueComponent
        }
    }

    var glowTrailColor: Color {
        get { Color(red: glowTrailR, green: glowTrailG, blue: glowTrailB) }
        set {
            guard let components = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            glowTrailR = components.redComponent
            glowTrailG = components.greenComponent
            glowTrailB = components.blueComponent
        }
    }

    var coreTrailNSColor: NSColor {
        NSColor(red: coreTrailR, green: coreTrailG, blue: coreTrailB, alpha: 1.0)
    }

    var glowTrailNSColor: NSColor {
        NSColor(red: glowTrailR, green: glowTrailG, blue: glowTrailB, alpha: 1.0)
    }

    var crosshairColor: Color {
        get { Color(red: crosshairR, green: crosshairG, blue: crosshairB) }
        set {
            guard let components = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            crosshairR = components.redComponent
            crosshairG = components.greenComponent
            crosshairB = components.blueComponent
        }
    }

    var crosshairNSColor: NSColor {
        NSColor(red: crosshairR, green: crosshairG, blue: crosshairB, alpha: crosshairOpacity)
    }

    // MARK: - Persistence

    private enum Keys {
        static let maxWidth = "trail.maxWidth"
        static let glowWidthMultiplier = "trail.glowWidthMultiplier"
        static let trailAlgorithm = "trail.algorithm"
        static let movementThreshold = "trail.movementThreshold"
        static let minimumVelocity = "trail.minimumVelocity"
        static let coreFadeTime = "trail.coreFadeTime"
        static let glowFadeTime = "trail.glowFadeTime"
        static let glowOuterOpacity = "trail.glowOuterOpacity"
        static let glowMiddleOpacity = "trail.glowMiddleOpacity"
        static let coreTrailR = "trail.coreTrailR"
        static let coreTrailG = "trail.coreTrailG"
        static let coreTrailB = "trail.coreTrailB"
        static let glowTrailR = "trail.glowTrailR"
        static let glowTrailG = "trail.glowTrailG"
        static let glowTrailB = "trail.glowTrailB"
        static let isTrailVisible = "trail.isTrailVisible"
        static let isRippleEnabled = "trail.isRippleEnabled"
        static let isCrosshairVisible = "visibility.isCrosshairVisible"
        static let crosshairR = "crosshair.r"
        static let crosshairG = "crosshair.g"
        static let crosshairB = "crosshair.b"
        static let crosshairOpacity = "crosshair.opacity"
        static let crosshairLineWidth = "crosshair.lineWidth"
        static let isShakeToggleEnabled = "input.isShakeToggleEnabled"
        static let shakeTimeWindow = "gesture.shakeTimeWindow"
        static let shakeRequiredReversals = "gesture.shakeRequiredReversals"
        static let shakeMinDisplacement = "gesture.shakeMinDisplacement"
        static let shakeMinVelocity = "gesture.shakeMinVelocity"
        static let shakeCooldown = "gesture.shakeCooldown"
        static let shakeAngularTolerance = "gesture.shakeAngularTolerance"
        static let circleTimeWindow = "gesture.circleTimeWindow"
        static let circleSampleWindow = "gesture.circleSampleWindow"
        static let circleMinRadius = "gesture.circleMinRadius"
        static let circleMinSpeed = "gesture.circleMinSpeed"
        static let circleCooldown = "gesture.circleCooldown"
        static let circleRequiredCircles = "gesture.circleRequiredCircles"
        static let circleMaxRadiusVariance = "gesture.circleMaxRadiusVariance"
        static let logLevelRaw = "app.logLevelRaw"
        static let rippleRadius = "ripple.radius"
        static let rippleSpeed = "ripple.speed"
        static let rippleWavelength = "ripple.wavelength"
        static let rippleDamping = "ripple.damping"
        static let rippleAmplitude = "ripple.amplitude"
        static let rippleDuration = "ripple.duration"
        static let rippleSpecularIntensity = "ripple.specularIntensity"
        static let reduceSyntheticSampleRate = "performance.reduceSyntheticSampleRate"
        static let enableSmoothInputCoalescing = "performance.enableSmoothInputCoalescing"
        static let useReducedLayerStack = "performance.useReducedLayerStack"
        static let onlyUpdateDirtyScreens = "performance.onlyUpdateDirtyScreens"
        static let useLinearSmoothPlaybackLookup = "performance.useLinearSmoothPlaybackLookup"
        static let useStrongerPointDecimation = "performance.useStrongerPointDecimation"
        static let useRelaxedPathRebuild = "performance.useRelaxedPathRebuild"
        static let capTrailRenderingTo60FPS = "performance.capTrailRenderingTo60FPS"
    }

    private var isSuppressingCallbacks = false

    /// Debounce window for UserDefaults writes. Rapid didSet firing (e.g. slider drag)
    /// coalesces into a single write after this interval of quiet.
    private static let saveDebounceInterval: TimeInterval = 0.3

    private var pendingSaveWork: DispatchWorkItem?

    /// Public save — debounces to one UserDefaults write per ~300ms of settling.
    /// Callbacks (`onChanged`, etc.) still fire immediately from each `didSet`
    /// so UI preview stays live.
    func save() {
        guard !isSuppressingCallbacks else { return }
        pendingSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeToDefaultsNow()
        }
        pendingSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: work)
    }

    /// Force any pending debounced write to complete synchronously. Call before app quit.
    func flushPendingSave() {
        guard let work = pendingSaveWork else { return }
        work.cancel()
        pendingSaveWork = nil
        writeToDefaultsNow()
    }

    /// Synchronous write — invoked by the debounce timer or `flushPendingSave`.
    private func writeToDefaultsNow() {
        pendingSaveWork = nil
        let d = UserDefaults.standard
        d.set(maxWidth, forKey: Keys.maxWidth)
        d.set(glowWidthMultiplier, forKey: Keys.glowWidthMultiplier)
        d.set(trailAlgorithm.rawValue, forKey: Keys.trailAlgorithm)
        d.set(movementThreshold, forKey: Keys.movementThreshold)
        d.set(minimumVelocity, forKey: Keys.minimumVelocity)
        d.set(coreFadeTime, forKey: Keys.coreFadeTime)
        d.set(glowFadeTime, forKey: Keys.glowFadeTime)
        d.set(glowOuterOpacity, forKey: Keys.glowOuterOpacity)
        d.set(glowMiddleOpacity, forKey: Keys.glowMiddleOpacity)
        d.set(coreTrailR, forKey: Keys.coreTrailR)
        d.set(coreTrailG, forKey: Keys.coreTrailG)
        d.set(coreTrailB, forKey: Keys.coreTrailB)
        d.set(glowTrailR, forKey: Keys.glowTrailR)
        d.set(glowTrailG, forKey: Keys.glowTrailG)
        d.set(glowTrailB, forKey: Keys.glowTrailB)
        d.set(isTrailVisible, forKey: Keys.isTrailVisible)
        d.set(isRippleEnabled, forKey: Keys.isRippleEnabled)
        d.set(isCrosshairVisible, forKey: Keys.isCrosshairVisible)
        d.set(crosshairR, forKey: Keys.crosshairR)
        d.set(crosshairG, forKey: Keys.crosshairG)
        d.set(crosshairB, forKey: Keys.crosshairB)
        d.set(crosshairOpacity, forKey: Keys.crosshairOpacity)
        d.set(crosshairLineWidth, forKey: Keys.crosshairLineWidth)
        d.set(isShakeToggleEnabled, forKey: Keys.isShakeToggleEnabled)
        d.set(shakeTimeWindow, forKey: Keys.shakeTimeWindow)
        d.set(shakeRequiredReversals, forKey: Keys.shakeRequiredReversals)
        d.set(shakeMinDisplacement, forKey: Keys.shakeMinDisplacement)
        d.set(shakeMinVelocity, forKey: Keys.shakeMinVelocity)
        d.set(shakeCooldown, forKey: Keys.shakeCooldown)
        d.set(shakeAngularTolerance, forKey: Keys.shakeAngularTolerance)
        d.set(circleTimeWindow, forKey: Keys.circleTimeWindow)
        d.set(circleSampleWindow, forKey: Keys.circleSampleWindow)
        d.set(circleMinRadius, forKey: Keys.circleMinRadius)
        d.set(circleMinSpeed, forKey: Keys.circleMinSpeed)
        d.set(circleCooldown, forKey: Keys.circleCooldown)
        d.set(circleRequiredCircles, forKey: Keys.circleRequiredCircles)
        d.set(circleMaxRadiusVariance, forKey: Keys.circleMaxRadiusVariance)
        d.set(logLevelRaw, forKey: Keys.logLevelRaw)
        d.set(rippleRadius, forKey: Keys.rippleRadius)
        d.set(rippleSpeed, forKey: Keys.rippleSpeed)
        d.set(rippleWavelength, forKey: Keys.rippleWavelength)
        d.set(rippleDamping, forKey: Keys.rippleDamping)
        d.set(rippleAmplitude, forKey: Keys.rippleAmplitude)
        d.set(rippleDuration, forKey: Keys.rippleDuration)
        d.set(rippleSpecularIntensity, forKey: Keys.rippleSpecularIntensity)
        d.set(reduceSyntheticSampleRate, forKey: Keys.reduceSyntheticSampleRate)
        d.set(enableSmoothInputCoalescing, forKey: Keys.enableSmoothInputCoalescing)
        d.set(useReducedLayerStack, forKey: Keys.useReducedLayerStack)
        d.set(onlyUpdateDirtyScreens, forKey: Keys.onlyUpdateDirtyScreens)
        d.set(useLinearSmoothPlaybackLookup, forKey: Keys.useLinearSmoothPlaybackLookup)
        d.set(useStrongerPointDecimation, forKey: Keys.useStrongerPointDecimation)
        d.set(useRelaxedPathRebuild, forKey: Keys.useRelaxedPathRebuild)
        d.set(capTrailRenderingTo60FPS, forKey: Keys.capTrailRenderingTo60FPS)
    }

    func restore() {
        let d = UserDefaults.standard
        isSuppressingCallbacks = true
        defer {
            isSuppressingCallbacks = false
            onChanged?()
            onVisibilityChanged?()
        }

        if d.object(forKey: Keys.maxWidth) != nil { maxWidth = d.double(forKey: Keys.maxWidth) }
        if d.object(forKey: Keys.glowWidthMultiplier) != nil { glowWidthMultiplier = d.double(forKey: Keys.glowWidthMultiplier) }
        if let rawValue = d.string(forKey: Keys.trailAlgorithm),
           let trailAlgorithm = TrailAlgorithm(rawValue: rawValue) {
            self.trailAlgorithm = trailAlgorithm
        }
        if d.object(forKey: Keys.movementThreshold) != nil { movementThreshold = d.double(forKey: Keys.movementThreshold) }
        if d.object(forKey: Keys.minimumVelocity) != nil { minimumVelocity = d.double(forKey: Keys.minimumVelocity) }
        if d.object(forKey: Keys.coreFadeTime) != nil { coreFadeTime = d.double(forKey: Keys.coreFadeTime) }
        if d.object(forKey: Keys.glowFadeTime) != nil { glowFadeTime = d.double(forKey: Keys.glowFadeTime) }
        if d.object(forKey: Keys.glowOuterOpacity) != nil { glowOuterOpacity = d.double(forKey: Keys.glowOuterOpacity) }
        if d.object(forKey: Keys.glowMiddleOpacity) != nil { glowMiddleOpacity = d.double(forKey: Keys.glowMiddleOpacity) }
        if d.object(forKey: Keys.coreTrailR) != nil { coreTrailR = d.double(forKey: Keys.coreTrailR) }
        if d.object(forKey: Keys.coreTrailG) != nil { coreTrailG = d.double(forKey: Keys.coreTrailG) }
        if d.object(forKey: Keys.coreTrailB) != nil { coreTrailB = d.double(forKey: Keys.coreTrailB) }
        if d.object(forKey: Keys.glowTrailR) != nil { glowTrailR = d.double(forKey: Keys.glowTrailR) }
        if d.object(forKey: Keys.glowTrailG) != nil { glowTrailG = d.double(forKey: Keys.glowTrailG) }
        if d.object(forKey: Keys.glowTrailB) != nil { glowTrailB = d.double(forKey: Keys.glowTrailB) }
        if d.object(forKey: Keys.isTrailVisible) != nil { isTrailVisible = d.bool(forKey: Keys.isTrailVisible) }
        if d.object(forKey: Keys.isRippleEnabled) != nil { isRippleEnabled = d.bool(forKey: Keys.isRippleEnabled) }
        if d.object(forKey: Keys.isCrosshairVisible) != nil { isCrosshairVisible = d.bool(forKey: Keys.isCrosshairVisible) }
        if d.object(forKey: Keys.crosshairR) != nil { crosshairR = d.double(forKey: Keys.crosshairR) }
        if d.object(forKey: Keys.crosshairG) != nil { crosshairG = d.double(forKey: Keys.crosshairG) }
        if d.object(forKey: Keys.crosshairB) != nil { crosshairB = d.double(forKey: Keys.crosshairB) }
        if d.object(forKey: Keys.crosshairOpacity) != nil { crosshairOpacity = d.double(forKey: Keys.crosshairOpacity) }
        if d.object(forKey: Keys.crosshairLineWidth) != nil { crosshairLineWidth = d.double(forKey: Keys.crosshairLineWidth) }
        if d.object(forKey: Keys.isShakeToggleEnabled) != nil { isShakeToggleEnabled = d.bool(forKey: Keys.isShakeToggleEnabled) }
        if d.object(forKey: Keys.shakeTimeWindow) != nil { shakeTimeWindow = d.double(forKey: Keys.shakeTimeWindow) }
        if d.object(forKey: Keys.shakeRequiredReversals) != nil { shakeRequiredReversals = d.integer(forKey: Keys.shakeRequiredReversals) }
        if d.object(forKey: Keys.shakeMinDisplacement) != nil { shakeMinDisplacement = d.double(forKey: Keys.shakeMinDisplacement) }
        if d.object(forKey: Keys.shakeMinVelocity) != nil { shakeMinVelocity = d.double(forKey: Keys.shakeMinVelocity) }
        if d.object(forKey: Keys.shakeCooldown) != nil { shakeCooldown = d.double(forKey: Keys.shakeCooldown) }
        if d.object(forKey: Keys.shakeAngularTolerance) != nil { shakeAngularTolerance = d.double(forKey: Keys.shakeAngularTolerance) }
        if d.object(forKey: Keys.circleTimeWindow) != nil { circleTimeWindow = d.double(forKey: Keys.circleTimeWindow) }
        if d.object(forKey: Keys.circleSampleWindow) != nil { circleSampleWindow = d.double(forKey: Keys.circleSampleWindow) }
        if d.object(forKey: Keys.circleMinRadius) != nil { circleMinRadius = d.double(forKey: Keys.circleMinRadius) }
        if d.object(forKey: Keys.circleMinSpeed) != nil { circleMinSpeed = d.double(forKey: Keys.circleMinSpeed) }
        if d.object(forKey: Keys.circleCooldown) != nil { circleCooldown = d.double(forKey: Keys.circleCooldown) }
        if d.object(forKey: Keys.circleRequiredCircles) != nil { circleRequiredCircles = d.integer(forKey: Keys.circleRequiredCircles) }
        if d.object(forKey: Keys.circleMaxRadiusVariance) != nil { circleMaxRadiusVariance = d.double(forKey: Keys.circleMaxRadiusVariance) }
        if d.object(forKey: Keys.logLevelRaw) != nil { logLevelRaw = d.integer(forKey: Keys.logLevelRaw); currentLogLevel = LogLevel(rawValue: logLevelRaw) ?? .info }
        if d.object(forKey: Keys.rippleRadius) != nil { rippleRadius = d.double(forKey: Keys.rippleRadius) }
        if d.object(forKey: Keys.rippleSpeed) != nil { rippleSpeed = d.double(forKey: Keys.rippleSpeed) }
        if d.object(forKey: Keys.rippleWavelength) != nil { rippleWavelength = d.double(forKey: Keys.rippleWavelength) }
        if d.object(forKey: Keys.rippleDamping) != nil { rippleDamping = d.double(forKey: Keys.rippleDamping) }
        if d.object(forKey: Keys.rippleAmplitude) != nil { rippleAmplitude = d.double(forKey: Keys.rippleAmplitude) }
        if d.object(forKey: Keys.rippleDuration) != nil { rippleDuration = d.double(forKey: Keys.rippleDuration) }
        if d.object(forKey: Keys.rippleSpecularIntensity) != nil { rippleSpecularIntensity = d.double(forKey: Keys.rippleSpecularIntensity) }
        if d.object(forKey: Keys.reduceSyntheticSampleRate) != nil { reduceSyntheticSampleRate = d.bool(forKey: Keys.reduceSyntheticSampleRate) }
        if d.object(forKey: Keys.enableSmoothInputCoalescing) != nil { enableSmoothInputCoalescing = d.bool(forKey: Keys.enableSmoothInputCoalescing) }
        if d.object(forKey: Keys.useReducedLayerStack) != nil { useReducedLayerStack = d.bool(forKey: Keys.useReducedLayerStack) }
        if d.object(forKey: Keys.onlyUpdateDirtyScreens) != nil { onlyUpdateDirtyScreens = d.bool(forKey: Keys.onlyUpdateDirtyScreens) }
        if d.object(forKey: Keys.useLinearSmoothPlaybackLookup) != nil { useLinearSmoothPlaybackLookup = d.bool(forKey: Keys.useLinearSmoothPlaybackLookup) }
        if d.object(forKey: Keys.useStrongerPointDecimation) != nil { useStrongerPointDecimation = d.bool(forKey: Keys.useStrongerPointDecimation) }
        if d.object(forKey: Keys.useRelaxedPathRebuild) != nil { useRelaxedPathRebuild = d.bool(forKey: Keys.useRelaxedPathRebuild) }
        if d.object(forKey: Keys.capTrailRenderingTo60FPS) != nil { capTrailRenderingTo60FPS = d.bool(forKey: Keys.capTrailRenderingTo60FPS) }
    }

    func apply(preset: TrailPreset) {
        isSuppressingCallbacks = true
        isTrailVisible = preset.isTrailVisible
        isRippleEnabled = preset.isRippleEnabled
        isCrosshairVisible = preset.isCrosshairVisible
        maxWidth = preset.maxWidth
        glowWidthMultiplier = preset.glowWidthMultiplier
        trailAlgorithm = preset.trailAlgorithm
        movementThreshold = preset.movementThreshold
        minimumVelocity = preset.minimumVelocity
        coreFadeTime = preset.coreFadeTime
        glowFadeTime = preset.glowFadeTime
        coreTrailR = preset.coreTrailR
        coreTrailG = preset.coreTrailG
        coreTrailB = preset.coreTrailB
        glowTrailR = preset.glowTrailR
        glowTrailG = preset.glowTrailG
        glowTrailB = preset.glowTrailB
        glowOuterOpacity = preset.glowOuterOpacity
        glowMiddleOpacity = preset.glowMiddleOpacity
        rippleRadius = preset.rippleRadius
        rippleSpeed = preset.rippleSpeed
        rippleWavelength = preset.rippleWavelength
        rippleDamping = preset.rippleDamping
        rippleAmplitude = preset.rippleAmplitude
        rippleDuration = preset.rippleDuration
        rippleSpecularIntensity = preset.rippleSpecularIntensity
        isShakeToggleEnabled = preset.isShakeToggleEnabled
        crosshairR = preset.crosshairR
        crosshairG = preset.crosshairG
        crosshairB = preset.crosshairB
        crosshairOpacity = preset.crosshairOpacity
        crosshairLineWidth = preset.crosshairLineWidth
        isSuppressingCallbacks = false
        save()
        onChanged?()
        onVisibilityChanged?()
    }

    func resetToDefaults() {
        isSuppressingCallbacks = true
        maxWidth = TrailSettingsDefaults.maxWidth
        glowWidthMultiplier = TrailSettingsDefaults.glowWidthMultiplier
        trailAlgorithm = TrailSettingsDefaults.trailAlgorithm
        movementThreshold = TrailSettingsDefaults.movementThreshold
        minimumVelocity = TrailSettingsDefaults.minimumVelocity
        coreFadeTime = TrailSettingsDefaults.coreFadeTime
        glowFadeTime = TrailSettingsDefaults.glowFadeTime
        glowOuterOpacity = TrailSettingsDefaults.glowOuterOpacity
        glowMiddleOpacity = TrailSettingsDefaults.glowMiddleOpacity
        coreTrailR = TrailSettingsDefaults.coreTrailR
        coreTrailG = TrailSettingsDefaults.coreTrailG
        coreTrailB = TrailSettingsDefaults.coreTrailB
        glowTrailR = TrailSettingsDefaults.glowTrailR
        glowTrailG = TrailSettingsDefaults.glowTrailG
        glowTrailB = TrailSettingsDefaults.glowTrailB
        isTrailVisible = TrailSettingsDefaults.isTrailVisible
        isRippleEnabled = TrailSettingsDefaults.isRippleEnabled
        isCrosshairVisible = TrailSettingsDefaults.isCrosshairVisible
        crosshairR = TrailSettingsDefaults.crosshairR
        crosshairG = TrailSettingsDefaults.crosshairG
        crosshairB = TrailSettingsDefaults.crosshairB
        crosshairOpacity = TrailSettingsDefaults.crosshairOpacity
        crosshairLineWidth = TrailSettingsDefaults.crosshairLineWidth
        isShakeToggleEnabled = TrailSettingsDefaults.isShakeToggleEnabled
        logLevelRaw = TrailSettingsDefaults.logLevelRaw
        rippleRadius = TrailSettingsDefaults.rippleRadius
        rippleSpeed = TrailSettingsDefaults.rippleSpeed
        rippleWavelength = TrailSettingsDefaults.rippleWavelength
        rippleDamping = TrailSettingsDefaults.rippleDamping
        rippleAmplitude = TrailSettingsDefaults.rippleAmplitude
        rippleDuration = TrailSettingsDefaults.rippleDuration
        rippleSpecularIntensity = TrailSettingsDefaults.rippleSpecularIntensity
        reduceSyntheticSampleRate = TrailSettingsDefaults.reduceSyntheticSampleRate
        enableSmoothInputCoalescing = TrailSettingsDefaults.enableSmoothInputCoalescing
        useReducedLayerStack = TrailSettingsDefaults.useReducedLayerStack
        onlyUpdateDirtyScreens = TrailSettingsDefaults.onlyUpdateDirtyScreens
        useLinearSmoothPlaybackLookup = TrailSettingsDefaults.useLinearSmoothPlaybackLookup
        useStrongerPointDecimation = TrailSettingsDefaults.useStrongerPointDecimation
        useRelaxedPathRebuild = TrailSettingsDefaults.useRelaxedPathRebuild
        capTrailRenderingTo60FPS = TrailSettingsDefaults.capTrailRenderingTo60FPS
        isSuppressingCallbacks = false
        save()
        onChanged?()
        onVisibilityChanged?()
    }

    func setAllPerformanceExperiments(enabled: Bool) {
        isSuppressingCallbacks = true
        reduceSyntheticSampleRate = enabled
        enableSmoothInputCoalescing = enabled
        useReducedLayerStack = enabled
        onlyUpdateDirtyScreens = enabled
        useLinearSmoothPlaybackLookup = enabled
        useStrongerPointDecimation = enabled
        useRelaxedPathRebuild = enabled
        capTrailRenderingTo60FPS = enabled
        isSuppressingCallbacks = false
        save()
        onChanged?()
    }
}
