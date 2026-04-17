/**
 * MouseTrail - A demonstration of macOS overlay windows and mouse tracking
 *
 * This application creates two floating windows:
 * 1. An information panel showing mouse coordinates, active app, and display info
 * 2. A red ball that follows the mouse cursor with a trailing animation
 *
 * Key concepts demonstrated:
 * - Custom NSPanel with selective mouse interaction
 * - Global event monitoring for mouse and keyboard
 * - Multi-window coordination
 * - Background app behavior (no Dock icon)
 * - Real-time UI updates with smooth animation
 */

import Cocoa
import QuartzCore
import ScreenCaptureKit
import SwiftUI

// Build timestamp - update this when making changes
let BUILD_TIMESTAMP = "2026-04-16 23:51:08"

@inline(__always)
func currentMonotonicTime() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}

/**
 * TrailPoint - Represents a single point in the mouse trail
 */
struct TrailPoint {
    let position: NSPoint
    let timestamp: TimeInterval
    let velocity: CGFloat // Speed in pixels per second
}

struct MouseSample {
    let location: NSPoint
    let timestamp: TimeInterval
}

struct SpringCursorState {
    var position: NSPoint
    var velocity: CGVector
    var timestamp: TimeInterval
}

struct PerformanceExperimentConfig {
    let reduceSyntheticSampleRate: Bool
    let enableSmoothInputCoalescing: Bool
    let useReducedLayerStack: Bool
    let onlyUpdateDirtyScreens: Bool
    let useLinearSmoothPlaybackLookup: Bool
    let useStrongerPointDecimation: Bool
    let useRelaxedPathRebuild: Bool
    let capTrailRenderingTo60FPS: Bool

    init(settings: TrailSettings) {
        reduceSyntheticSampleRate = settings.reduceSyntheticSampleRate
        enableSmoothInputCoalescing = settings.enableSmoothInputCoalescing
        useReducedLayerStack = settings.useReducedLayerStack
        onlyUpdateDirtyScreens = settings.onlyUpdateDirtyScreens
        useLinearSmoothPlaybackLookup = settings.useLinearSmoothPlaybackLookup
        useStrongerPointDecimation = settings.useStrongerPointDecimation
        useRelaxedPathRebuild = settings.useRelaxedPathRebuild
        capTrailRenderingTo60FPS = settings.capTrailRenderingTo60FPS
    }

    func mouseCoalescingEnabled(for algorithm: TrailAlgorithm) -> Bool {
        switch algorithm {
        case .spring:
            return true
        case .smooth:
            return enableSmoothInputCoalescing
        }
    }

    var syntheticSampleInterval: TimeInterval {
        reduceSyntheticSampleRate ? (1.0 / 120.0) : (1.0 / 240.0)
    }

    var trailMinimumPointDistance: CGFloat {
        useStrongerPointDecimation ? 1.5 : 0.5
    }

    var trailMaximumRenderSegmentLength: CGFloat {
        useRelaxedPathRebuild ? 10.0 : 6.0
    }

    var trailRenderSmoothingPasses: Int {
        useRelaxedPathRebuild ? 1 : 2
    }

    var trailMaxPoints: Int {
        useRelaxedPathRebuild ? 120 : 180
    }

    var trailRenderMinimumInterval: TimeInterval {
        capTrailRenderingTo60FPS ? (1.0 / 60.0) : 0
    }
}

/**
 * TrailView - Hardware-accelerated view that renders a smooth mouse trail
 * 
 * Uses CAShapeLayer and Catmull-Rom spline interpolation for smooth curves
 * with glow effects and continuous path rendering.
 */
class TrailView: NSView {
    /// Maximum number of points to keep in trail
    var maxPoints = 180
    let fullWidthPointCount: CGFloat = 40
    var minimumPointDistance: CGFloat = 0.5
    var maximumRenderSegmentLength: CGFloat = 6.0
    var renderSmoothingPasses = 2
    let interpolationAlpha: CGFloat = 0.5
    
    /// Fade time in seconds for core trail
    var fadeTime: TimeInterval = 0.6
    
    /// Fade time for glow trail (faster)
    var glowFadeTime: TimeInterval = 0.35
    
    /// Base and max width for trail
    let baseWidth: CGFloat = 0.5
    var maxWidth: CGFloat = 8.0
    
    /// Glow width multiplier
    var glowWidthMultiplier: CGFloat = 3.5
    
    /// Core trail color
    var coreColor = NSColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 1.0)
    
    /// Glow trail color
    var glowColor = NSColor(red: 0.1, green: 0.5, blue: 1.0, alpha: 1.0)
    
    /// Glow opacity values
    var glowOuterOpacity: CGFloat = 0.02
    var glowMiddleOpacity: CGFloat = 0.08
    
    /// Points in the trail
    private var points: [TrailPoint] = []

    var usesReducedLayerStack = false {
        didSet {
            updateLayerVisibility()
        }
    }
    
    /// Movement threshold tracking
    private var startPosition: NSPoint?
    private var isTrailActive = false
    private var lastMovementTime: TimeInterval = 0
    var movementThreshold: CGFloat = 30.0  // pixels
    var inactivityTimeout: TimeInterval = 0.5  // seconds
    var minimumVelocity: CGFloat = 0.0  // pixels per second (default to 0 for immediate trail)
    
    /// Layers for core trail effect
    private let coreOuterLayer = CAShapeLayer()
    private let coreMiddleLayer = CAShapeLayer()
    private let coreInnerLayer = CAShapeLayer()
    private let gradientMaskLayer = CAGradientLayer()

    /// Layers for glow trail effect
    private let glowOuterLayer = CAShapeLayer()
    private let glowMiddleLayer = CAShapeLayer()
    private let glowInnerLayer = CAShapeLayer()

    /// Crosshair layers
    private let crosshairVerticalLayer = CAShapeLayer()
    private let crosshairHorizontalLayer = CAShapeLayer()
    private var lastCrosshairPoint: NSPoint?
    var isCrosshairVisible = false {
        didSet {
            crosshairVerticalLayer.isHidden = !isCrosshairVisible
            crosshairHorizontalLayer.isHidden = !isCrosshairVisible
            if !isCrosshairVisible { lastCrosshairPoint = nil }
        }
    }

    private var activeCoreLayers: [CAShapeLayer] {
        usesReducedLayerStack ? [coreMiddleLayer, coreInnerLayer] : [coreOuterLayer, coreMiddleLayer, coreInnerLayer]
    }

    private var activeGlowLayers: [CAShapeLayer] {
        usesReducedLayerStack ? [glowMiddleLayer, glowInnerLayer] : [glowOuterLayer, glowMiddleLayer, glowInnerLayer]
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        
        // Outer glow layer (widest, most transparent)
        coreOuterLayer.fillColor = nil
        coreOuterLayer.strokeColor = coreColor.withAlphaComponent(0.08).cgColor
        coreOuterLayer.lineWidth = maxWidth * 3.0
        coreOuterLayer.lineCap = .round
        coreOuterLayer.lineJoin = .round
        coreOuterLayer.shadowColor = coreColor.cgColor
        coreOuterLayer.shadowRadius = 8
        coreOuterLayer.shadowOpacity = 0.2
        coreOuterLayer.shadowOffset = .zero
        coreOuterLayer.frame = bounds
        coreOuterLayer.masksToBounds = false
        coreOuterLayer.shouldRasterize = false
        coreOuterLayer.rasterizationScale = 2.0 // Retina quality
        
        // Middle glow layer
        coreMiddleLayer.fillColor = nil
        coreMiddleLayer.strokeColor = coreColor.withAlphaComponent(0.25).cgColor
        coreMiddleLayer.lineWidth = maxWidth * 1.8
        coreMiddleLayer.lineCap = .round
        coreMiddleLayer.lineJoin = .round
        coreMiddleLayer.shadowColor = coreColor.cgColor
        coreMiddleLayer.shadowRadius = 3
        coreMiddleLayer.shadowOpacity = 0.3
        coreMiddleLayer.shadowOffset = .zero
        coreMiddleLayer.frame = bounds
        coreMiddleLayer.masksToBounds = false
        coreMiddleLayer.shouldRasterize = false
        coreMiddleLayer.rasterizationScale = 2.0
        
        // Core layer (brightest, thinnest)
        coreInnerLayer.fillColor = nil
        coreInnerLayer.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        coreInnerLayer.lineWidth = maxWidth * 0.3
        coreInnerLayer.lineCap = .round
        coreInnerLayer.lineJoin = .round
        coreInnerLayer.shadowColor = NSColor.white.cgColor
        coreInnerLayer.shadowRadius = 1
        coreInnerLayer.shadowOpacity = 0.4
        coreInnerLayer.shadowOffset = .zero
        coreInnerLayer.frame = bounds
        coreInnerLayer.masksToBounds = false
        coreInnerLayer.shouldRasterize = false
        coreInnerLayer.rasterizationScale = 2.0
        
        // Glow outer layer (widest overall) - steeper opacity falloff
        glowOuterLayer.fillColor = nil
        glowOuterLayer.strokeColor = glowColor.withAlphaComponent(glowOuterOpacity).cgColor
        glowOuterLayer.lineWidth = maxWidth * 3.0 * glowWidthMultiplier
        glowOuterLayer.lineCap = .round
        glowOuterLayer.lineJoin = .round
        glowOuterLayer.shadowColor = glowColor.cgColor
        glowOuterLayer.shadowRadius = 10
        glowOuterLayer.shadowOpacity = 0.1
        glowOuterLayer.shadowOffset = .zero
        glowOuterLayer.frame = bounds
        glowOuterLayer.masksToBounds = false
        glowOuterLayer.shouldRasterize = false
        glowOuterLayer.rasterizationScale = 2.0
        
        // Glow middle layer - steeper opacity
        glowMiddleLayer.fillColor = nil
        glowMiddleLayer.strokeColor = glowColor.withAlphaComponent(glowMiddleOpacity).cgColor
        glowMiddleLayer.lineWidth = maxWidth * 1.8 * glowWidthMultiplier
        glowMiddleLayer.lineCap = .round
        glowMiddleLayer.lineJoin = .round
        glowMiddleLayer.shadowColor = glowColor.cgColor
        glowMiddleLayer.shadowRadius = 4
        glowMiddleLayer.shadowOpacity = 0.15
        glowMiddleLayer.shadowOffset = .zero
        glowMiddleLayer.frame = bounds
        glowMiddleLayer.masksToBounds = false
        glowMiddleLayer.shouldRasterize = false
        glowMiddleLayer.rasterizationScale = 2.0
        
        // Glow inner layer
        glowInnerLayer.fillColor = nil
        glowInnerLayer.strokeColor = NSColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.9).cgColor
        glowInnerLayer.lineWidth = maxWidth * 0.4 * glowWidthMultiplier
        glowInnerLayer.lineCap = .round
        glowInnerLayer.lineJoin = .round
        glowInnerLayer.shadowColor = NSColor.white.cgColor
        glowInnerLayer.shadowRadius = 1
        glowInnerLayer.shadowOpacity = 0.3
        glowInnerLayer.shadowOffset = .zero
        glowInnerLayer.frame = bounds
        glowInnerLayer.masksToBounds = false
        glowInnerLayer.shouldRasterize = false
        glowInnerLayer.rasterizationScale = 2.0
        
        // Create container for all trail layers
        let trailContainer = CALayer()
        trailContainer.frame = bounds
        trailContainer.masksToBounds = false
        // Add core layers first (bottom)
        trailContainer.addSublayer(coreOuterLayer)
        trailContainer.addSublayer(coreMiddleLayer)
        trailContainer.addSublayer(coreInnerLayer)
        // Add glow layers on top
        trailContainer.addSublayer(glowOuterLayer)
        trailContainer.addSublayer(glowMiddleLayer)
        trailContainer.addSublayer(glowInnerLayer)
        
        // Setup gradient mask for smooth fading
        gradientMaskLayer.frame = bounds
        gradientMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientMaskLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.3).cgColor,
            NSColor.black.withAlphaComponent(0.8).cgColor,
            NSColor.black.cgColor
        ]
        gradientMaskLayer.locations = [0, 0.3, 0.7, 1]
        
        layer?.addSublayer(trailContainer)

        // Crosshair layers — lines spanning full screen
        crosshairVerticalLayer.fillColor = nil
        crosshairVerticalLayer.frame = bounds
        crosshairVerticalLayer.isHidden = true

        crosshairHorizontalLayer.fillColor = nil
        crosshairHorizontalLayer.frame = bounds
        crosshairHorizontalLayer.isHidden = true

        applyCrosshairStyle(color: NSColor.white.withAlphaComponent(0.3), lineWidth: 1.0)

        layer?.addSublayer(crosshairVerticalLayer)
        layer?.addSublayer(crosshairHorizontalLayer)

        updateLayerVisibility()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }
    
    override var frame: NSRect {
        didSet {
            // Update all layer frames when view frame changes
            coreOuterLayer.frame = bounds
            coreMiddleLayer.frame = bounds
            coreInnerLayer.frame = bounds
            glowOuterLayer.frame = bounds
            glowMiddleLayer.frame = bounds
            glowInnerLayer.frame = bounds
            gradientMaskLayer.frame = bounds
            crosshairVerticalLayer.frame = bounds
            crosshairHorizontalLayer.frame = bounds
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

    private func add(_ lhs: NSPoint, _ rhs: NSPoint) -> NSPoint {
        NSPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    private func subtract(_ lhs: NSPoint, _ rhs: NSPoint) -> NSPoint {
        NSPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    private func scale(_ point: NSPoint, by scalar: CGFloat) -> NSPoint {
        NSPoint(x: point.x * scalar, y: point.y * scalar)
    }

    private func extrapolatedEndpoint(from point: NSPoint, toward neighbor: NSPoint) -> NSPoint {
        add(point, subtract(point, neighbor))
    }

    private func weightedAverage(_ weightedPoints: [(NSPoint, CGFloat)]) -> NSPoint {
        var totalWeight: CGFloat = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0

        for (point, weight) in weightedPoints {
            totalWeight += weight
            sumX += point.x * weight
            sumY += point.y * weight
        }

        guard totalWeight > 0 else { return .zero }
        return NSPoint(x: sumX / totalWeight, y: sumY / totalWeight)
    }

    private func densifiedPositions(from positions: [NSPoint], maximumSegmentLength: CGFloat) -> [NSPoint] {
        guard positions.count >= 2 else { return positions }

        var densePositions: [NSPoint] = [positions[0]]

        for index in 0..<(positions.count - 1) {
            let start = positions[index]
            let end = positions[index + 1]
            let distance = pointDistance(start, end)
            let subdivisions = max(1, Int(ceil(distance / maximumSegmentLength)))

            if subdivisions > 1 {
                for step in 1..<subdivisions {
                    let factor = CGFloat(step) / CGFloat(subdivisions)
                    densePositions.append(interpolate(start, end, factor: factor))
                }
            }

            densePositions.append(end)
        }

        return densePositions
    }

    private func smoothedPositions(from positions: [NSPoint], passes: Int) -> [NSPoint] {
        guard positions.count >= 3, passes > 0 else { return positions }

        var currentPositions = positions

        for _ in 0..<passes {
            guard currentPositions.count >= 3 else { break }

            var nextPositions = currentPositions

            for index in 1..<(currentPositions.count - 1) {
                if index >= 2 && (index + 2) < currentPositions.count {
                    nextPositions[index] = weightedAverage([
                        (currentPositions[index - 2], 1),
                        (currentPositions[index - 1], 4),
                        (currentPositions[index], 6),
                        (currentPositions[index + 1], 4),
                        (currentPositions[index + 2], 1)
                    ])
                } else {
                    nextPositions[index] = weightedAverage([
                        (currentPositions[index - 1], 1),
                        (currentPositions[index], 2),
                        (currentPositions[index + 1], 1)
                    ])
                }
            }

            nextPositions[0] = positions[0]
            nextPositions[nextPositions.count - 1] = positions[positions.count - 1]
            currentPositions = nextPositions
        }

        return currentPositions
    }

    private func renderPositions(from trailPoints: [TrailPoint]) -> [NSPoint] {
        let rawPositions = trailPoints.map(\.position)
        let densePositions = densifiedPositions(
            from: rawPositions,
            maximumSegmentLength: maximumRenderSegmentLength
        )
        return smoothedPositions(from: densePositions, passes: renderSmoothingPasses)
    }

    private func parameterizedTime(from start: NSPoint, to end: NSPoint, previous: CGFloat) -> CGFloat {
        let distance = max(pointDistance(start, end), 0.0001)
        return previous + pow(distance, interpolationAlpha)
    }

    private func blend(_ start: NSPoint, _ end: NSPoint, t0: CGFloat, t1: CGFloat, t: CGFloat) -> NSPoint {
        let denominator = max(t1 - t0, 0.0001)
        let factor = (t - t0) / denominator
        return interpolate(start, end, factor: factor)
    }

    private func centripetalCatmullRomPoint(_ p0: NSPoint, _ p1: NSPoint, _ p2: NSPoint, _ p3: NSPoint, t: CGFloat) -> NSPoint {
        let t0: CGFloat = 0
        let t1 = parameterizedTime(from: p0, to: p1, previous: t0)
        let t2 = parameterizedTime(from: p1, to: p2, previous: t1)
        let t3 = parameterizedTime(from: p2, to: p3, previous: t2)
        let interpolatedT = t1 + ((t2 - t1) * t)

        let a1 = blend(p0, p1, t0: t0, t1: t1, t: interpolatedT)
        let a2 = blend(p1, p2, t0: t1, t1: t2, t: interpolatedT)
        let a3 = blend(p2, p3, t0: t2, t1: t3, t: interpolatedT)

        let b1 = blend(a1, a2, t0: t0, t1: t2, t: interpolatedT)
        let b2 = blend(a2, a3, t0: t1, t1: t3, t: interpolatedT)

        return blend(b1, b2, t0: t1, t1: t2, t: interpolatedT)
    }

    private func catmullRomTangents(
        _ p0: NSPoint,
        _ p1: NSPoint,
        _ p2: NSPoint,
        _ p3: NSPoint
    ) -> (start: NSPoint, end: NSPoint) {
        let t0: CGFloat = 0
        let t1 = parameterizedTime(from: p0, to: p1, previous: t0)
        let t2 = parameterizedTime(from: p1, to: p2, previous: t1)
        let t3 = parameterizedTime(from: p2, to: p3, previous: t2)

        let dt10 = max(t1 - t0, 0.0001)
        let dt20 = max(t2 - t0, 0.0001)
        let dt21 = max(t2 - t1, 0.0001)
        let dt31 = max(t3 - t1, 0.0001)
        let dt32 = max(t3 - t2, 0.0001)

        let startTerm1 = scale(subtract(p1, p0), by: 1.0 / dt10)
        let startTerm2 = scale(subtract(p2, p0), by: 1.0 / dt20)
        let startTerm3 = scale(subtract(p2, p1), by: 1.0 / dt21)
        let startTangent = scale(
            add(subtract(startTerm1, startTerm2), startTerm3),
            by: dt21
        )

        let endTerm1 = scale(subtract(p2, p1), by: 1.0 / dt21)
        let endTerm2 = scale(subtract(p3, p1), by: 1.0 / dt31)
        let endTerm3 = scale(subtract(p3, p2), by: 1.0 / dt32)
        let endTangent = scale(
            add(subtract(endTerm1, endTerm2), endTerm3),
            by: dt21
        )

        return (start: startTangent, end: endTangent)
    }

    private func clearTrailLayers(_ layers: [CAShapeLayer]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers {
            layer.path = nil
            layer.shadowPath = nil
        }
        CATransaction.commit()
    }

    private func updateLayerVisibility() {
        coreOuterLayer.isHidden = usesReducedLayerStack
        glowOuterLayer.isHidden = usesReducedLayerStack

        if usesReducedLayerStack {
            clearTrailLayers([coreOuterLayer, glowOuterLayer].compactMap { $0 })
        }
    }

    func resetTrail() {
        points.removeAll()
        startPosition = nil
        isTrailActive = false
        lastMovementTime = 0
        clearTrailLayers([coreOuterLayer, coreMiddleLayer, coreInnerLayer])
        clearTrailLayers([glowOuterLayer, glowMiddleLayer, glowInnerLayer])
    }

    private func applyLineWidths(for trailPoints: [TrailPoint], to layers: [CAShapeLayer], isBlue: Bool) {
        let progress = min(CGFloat(trailPoints.count) / fullWidthPointCount, 1.0)
        let trailWidth = baseWidth + (maxWidth - baseWidth) * progress
        let widthMultiplier = isBlue ? glowWidthMultiplier : 1.0
        let widthFactors: [CGFloat] = (layers.count >= 3) ? [3.0, 1.8, 0.3] : [1.8, 0.3]

        guard layers.count == widthFactors.count else { return }

        for (layer, factor) in zip(layers, widthFactors) {
            layer.lineWidth = trailWidth * factor * widthMultiplier
        }
    }

    private func shadowPath(for path: CGPath, lineWidth: CGFloat) -> CGPath {
        path.copy(
            strokingWithWidth: max(lineWidth, 0.1),
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10
        )
    }

    /// Add a new point to the trail
    @discardableResult
    func addPoint(_ point: NSPoint, at now: TimeInterval = currentMonotonicTime()) -> Bool {
        // Convert screen coordinates to view coordinates
        guard let window = self.window else { return false }
        
        // Check if the point is within this screen's bounds
        let screenFrame = window.frame
        guard screenFrame.insetBy(dx: -1, dy: -1).contains(point) else { return false }
        
        // Convert to view-local coordinates
        let viewPoint = NSPoint(
            x: point.x - screenFrame.origin.x,
            y: point.y - screenFrame.origin.y
        )
        
        // Check for inactivity timeout
        if now - lastMovementTime > inactivityTimeout {
            // Reset trail after inactivity
            isTrailActive = false
            startPosition = nil
            points.removeAll()
        }
        
        lastMovementTime = now
        
        // Check movement threshold
        if !isTrailActive {
            if startPosition == nil {
                startPosition = viewPoint
                return false  // Don't start trail yet
            }
            
            // Calculate distance from start position
            if let start = startPosition {
                let distance = pointDistance(viewPoint, start)
                
                if distance < movementThreshold {
                    return false  // Still below threshold
                }
                
                // Threshold reached, activate trail
                isTrailActive = true
            }
        }
        
        // Calculate velocity if we have a previous point
        var velocity: CGFloat = 0
        var distanceFromLastPoint: CGFloat = 0
        
        if let lastPoint = points.last {
            let distance = pointDistance(viewPoint, lastPoint.position)
            let timeDelta = now - lastPoint.timestamp
            distanceFromLastPoint = distance
            
            if timeDelta > 0 {
                velocity = distance / CGFloat(timeDelta)
            }
        }

        if distanceFromLastPoint < minimumPointDistance && !points.isEmpty {
            return false
        }
        
        // Check if velocity is too low
        if velocity < minimumVelocity && !points.isEmpty {
            // Reset trail if moving too slowly
            isTrailActive = false
            startPosition = nil
            points.removeAll()
            return true
        }
        
        // Add the point to trail
        let trailPoint = TrailPoint(position: viewPoint, timestamp: now, velocity: velocity)
        points.append(trailPoint)
        
        // Limit points
        if points.count > maxPoints {
            points.removeFirst()
        }

        return true
    }
    
    /// Check if trail has visible points
    func hasVisiblePoints(at now: TimeInterval = currentMonotonicTime()) -> Bool {
        return points.contains { now - $0.timestamp < fadeTime }
    }
    
    /// Update layer colors and properties when values change
    func updateLayerProperties() {
        // Update core trail color
        coreOuterLayer.strokeColor = coreColor.withAlphaComponent(0.08).cgColor
        coreOuterLayer.shadowColor = coreColor.cgColor
        coreMiddleLayer.strokeColor = coreColor.withAlphaComponent(0.2).cgColor
        coreMiddleLayer.shadowColor = coreColor.cgColor
        coreInnerLayer.strokeColor = coreColor.withAlphaComponent(0.9).cgColor
        coreInnerLayer.shadowColor = coreColor.cgColor

        // Update glow trail color and opacity
        glowOuterLayer.strokeColor = glowColor.withAlphaComponent(glowOuterOpacity).cgColor
        glowOuterLayer.shadowColor = glowColor.cgColor
        glowMiddleLayer.strokeColor = glowColor.withAlphaComponent(glowMiddleOpacity).cgColor
        glowMiddleLayer.shadowColor = glowColor.cgColor
        glowInnerLayer.strokeColor = NSColor(red: 0.7 * glowColor.redComponent,
                                           green: 0.85 * glowColor.greenComponent,
                                           blue: glowColor.blueComponent,
                                           alpha: 0.9).cgColor
    }
    
    /// Update the trail path
    func updateTrail(at now: TimeInterval = currentMonotonicTime()) {
        // Remove old points
        points.removeAll { now - $0.timestamp > fadeTime }

        guard !points.isEmpty else {
            clearTrailLayers([coreOuterLayer, coreMiddleLayer, coreInnerLayer])
            clearTrailLayers([glowOuterLayer, glowMiddleLayer, glowInnerLayer])
            return
        }

        // Build core trail
        buildTrailPath(for: points, layers: activeCoreLayers)

        // Build glow trail with shorter fade
        let bluePoints = points.filter { now - $0.timestamp <= glowFadeTime }
        buildTrailPath(for: bluePoints, layers: activeGlowLayers, isBlue: true)
    }
    
    /// Build trail path for given points and layers
    private func buildTrailPath(for trailPoints: [TrailPoint], layers: [CAShapeLayer], isBlue: Bool = false) {
        let renderPositions = renderPositions(from: trailPoints)

        guard renderPositions.count >= 2 else {
            clearTrailLayers(layers)
            return
        }
        
        // Round the sampled centerline before fitting curves so quick arcs do not
        // collapse into visible straight shortcuts between sparse input samples.
        let path = CGMutablePath()
        path.move(to: renderPositions[0])

        for i in 0..<(renderPositions.count - 1) {
            let p1 = renderPositions[i]
            let p2 = renderPositions[i + 1]
            let p0 = i > 0
                ? renderPositions[i - 1]
                : extrapolatedEndpoint(from: p1, toward: p2)
            let p3 = (i + 2 < renderPositions.count)
                ? renderPositions[i + 2]
                : extrapolatedEndpoint(from: p2, toward: p1)
            let tangents = catmullRomTangents(p0, p1, p2, p3)
            let control1 = add(p1, scale(tangents.start, by: 1.0 / 3.0))
            let control2 = subtract(p2, scale(tangents.end, by: 1.0 / 3.0))
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        applyLineWidths(for: trailPoints, to: layers, isBlue: isBlue)

        // Apply path to all layers
        for layer in layers {
            layer.path = path
            layer.shadowPath = shadowPath(for: path, lineWidth: layer.lineWidth)
        }
        
        CATransaction.commit()
    }


    /// Update crosshair position (viewPoint is in view-local coordinates)
    func updateCrosshair(at viewPoint: NSPoint) {
        guard isCrosshairVisible else { return }

        // Skip redundant redraws when mouse hasn't moved
        if let last = lastCrosshairPoint,
           abs(last.x - viewPoint.x) < 0.5 && abs(last.y - viewPoint.y) < 0.5 {
            return
        }
        lastCrosshairPoint = viewPoint

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let verticalPath = CGMutablePath()
        verticalPath.move(to: CGPoint(x: viewPoint.x, y: 0))
        verticalPath.addLine(to: CGPoint(x: viewPoint.x, y: bounds.height))
        crosshairVerticalLayer.path = verticalPath

        let horizontalPath = CGMutablePath()
        horizontalPath.move(to: CGPoint(x: 0, y: viewPoint.y))
        horizontalPath.addLine(to: CGPoint(x: bounds.width, y: viewPoint.y))
        crosshairHorizontalLayer.path = horizontalPath

        CATransaction.commit()
    }

    /// Apply crosshair color and line width to both layers.
    func applyCrosshairStyle(color: NSColor, lineWidth: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        crosshairVerticalLayer.strokeColor = color.cgColor
        crosshairVerticalLayer.lineWidth = lineWidth
        crosshairHorizontalLayer.strokeColor = color.cgColor
        crosshairHorizontalLayer.lineWidth = lineWidth
        CATransaction.commit()
    }

    /// Clear crosshair paths
    func clearCrosshair() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        crosshairVerticalLayer.path = nil
        crosshairHorizontalLayer.path = nil
        CATransaction.commit()
        lastCrosshairPoint = nil
    }
}

/**
 * RippleEffect - Represents a single ripple distortion effect
 *
 * This class manages the lifecycle of a ripple effect from click to fade out,
 * including screen capture, distortion animation, and window management.
 */
class RippleEffect {
    /// Shared CIKernel loaded from the bundled metallib
    private static var _rippleKernel: CIKernel?
    private static var _kernelLoadAttempted = false
    private static let sharedCIContext = CIContext(options: [
        .useSoftwareRenderer: false,
        // Each ripple is short-lived, so retaining intermediate textures per instance
        // creates avoidable GPU memory churn.
        .cacheIntermediates: false
    ])

    static var rippleKernel: CIKernel? {
        if !_kernelLoadAttempted {
            _kernelLoadAttempted = true
            var url = Bundle.main.url(forResource: "RippleKernel", withExtension: "metallib")
            // Fallback: look in Resources relative to executable
            if url == nil {
                let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                let siblingURL = execURL.deletingLastPathComponent()
                    .appendingPathComponent("../Resources/RippleKernel.metallib")
                if FileManager.default.fileExists(atPath: siblingURL.path) {
                    url = siblingURL
                }
            }
            if let url = url, let data = try? Data(contentsOf: url) {
                do {
                    _rippleKernel = try CIKernel(functionName: "rippleDisplacement",
                                                   fromMetalLibraryData: data)
                    logInfo("Metal ripple kernel loaded successfully")
                } catch {
                    logInfo("Failed to create CIKernel from metallib: \(error)")
                }
            } else {
                logInfo("RippleKernel.metallib not found in bundle")
            }
        }
        return _rippleKernel
    }

    /// Click location in screen coordinates
    let clickLocation: NSPoint

    /// Captured screen content around click point
    let capturedImage: CGImage

    /// Timestamp when ripple started
    let startTime: TimeInterval

    /// Current animation radius (starts at 0, animates to max)
    var currentRadius: CGFloat = 0

    /// Window displaying the ripple
    let window: NSPanel

    /// Container view with circular mask
    let containerView: NSView

    /// Image view showing distorted content
    let imageView: NSImageView

    /// Core Image context for filtering
    let ciContext: CIContext

    /// Maximum radius for the ripple
    let maxRadius: CGFloat

    /// Ripple parameters
    let animationDuration: TimeInterval
    let speed: CGFloat
    let wavelength: CGFloat
    let damping: CGFloat
    let amplitude: CGFloat
    let specularIntensity: CGFloat

    init(at location: NSPoint, capturedImage: CGImage, maxRadius: CGFloat,
         speed: CGFloat = 120, wavelength: CGFloat = 25, damping: CGFloat = 2.0,
         amplitude: CGFloat = 12, duration: TimeInterval = 1.2, specularIntensity: CGFloat = 0.8) {
        debugLog("Creating RippleEffect at location: \(location)")
        self.clickLocation = location
        self.capturedImage = capturedImage
        self.startTime = Date().timeIntervalSince1970
        self.currentRadius = 0 // Start from center
        self.maxRadius = maxRadius
        self.speed = speed
        self.wavelength = wavelength
        self.damping = damping
        self.amplitude = amplitude
        self.animationDuration = duration
        self.specularIntensity = specularIntensity
        
        // Reuse a single CIContext so repeated clicks do not recreate GPU-backed caches.
        self.ciContext = Self.sharedCIContext
        
        // Create window for ripple effect
        let windowSize: CGFloat = maxRadius * 2
        let windowRect = NSRect(
            x: location.x - maxRadius,
            y: location.y - maxRadius,
            width: windowSize,
            height: windowSize
        )
        
        debugLog("Ripple window rect: \(windowRect)")
        debugLog("Ripple window center: (\(windowRect.midX), \(windowRect.midY))")
        
        self.window = NSPanel(
            contentRect: windowRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configure window
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 2) // Above trail and menu bar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
            .stationary
        ]
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        
        // Create container view with circular mask
        self.containerView = NSView(frame: window.contentView!.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Create circular mask layer
        let maskLayer = CAShapeLayer()
        let circlePath = CGPath(ellipseIn: containerView.bounds, transform: nil)
        maskLayer.path = circlePath
        maskLayer.fillColor = NSColor.white.cgColor // Make sure mask is white
        containerView.layer?.mask = maskLayer
        
        window.contentView?.addSubview(containerView)
        
        // Create image view inside container - larger than container to accommodate the extra capture area
        let imageSize = CGFloat(capturedImage.width)
        let containerSize = containerView.bounds.width
        let offset = (imageSize - containerSize) / 2
        
        self.imageView = NSImageView(frame: NSRect(
            x: -offset,
            y: -offset,
            width: imageSize,
            height: imageSize
        ))
        imageView.imageScaling = .scaleNone // Don't scale the image
        imageView.wantsLayer = true
        containerView.addSubview(imageView)
        
        // Show window
        window.orderFront(nil)
        debugLog("Ripple window created and shown with size: \(windowSize)x\(windowSize)")
        
        // Do initial update to set the image
        _ = update()
    }
    
    /// Update the ripple animation
    func update() -> Bool {
        let elapsed = Date().timeIntervalSince1970 - startTime
        let progress = min(elapsed / animationDuration, 1.0)

        // Animation complete
        if progress >= 1.0 {
            return false
        }

        // Calculate fade (starts at 0.6 progress)
        let fadeStart: CGFloat = 0.6
        let opacity = progress < fadeStart ? 1.0 : 1.0 - ((progress - fadeStart) / (1.0 - fadeStart))

        // Always update fade regardless of distortion success
        containerView.alphaValue = opacity

        // Apply Metal shader distortion
        if let distortedImage = applyRippleDistortion() {
            imageView.image = distortedImage
        }

        return true
    }
    
    /// Apply ripple distortion using Metal CIKernel
    private func applyRippleDistortion() -> NSImage? {
        guard let kernel = RippleEffect.rippleKernel else {
            debugLog("Ripple kernel not available")
            return nil
        }

        let ciImage = CIImage(cgImage: capturedImage)
        let imageCenter = CGPoint(x: ciImage.extent.width / 2, y: ciImage.extent.height / 2)
        let elapsed = Date().timeIntervalSince1970 - startTime
        let fadeRadius = maxRadius

        guard let outputImage = kernel.apply(
            extent: ciImage.extent,
            roiCallback: { [amplitude] _, rect in
                return rect.insetBy(dx: -amplitude, dy: -amplitude)
            },
            arguments: [
                ciImage,
                CIVector(x: imageCenter.x, y: imageCenter.y),
                Float(elapsed),
                Float(speed),
                Float(wavelength),
                Float(damping),
                Float(amplitude),
                Float(fadeRadius),
                Float(specularIntensity)
            ]
        ) else {
            debugLog("Kernel apply returned nil")
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgImage = ciContext.createCGImage(outputImage, from: ciImage.extent,
                                                     format: .RGBA8, colorSpace: colorSpace) else {
            debugLog("Failed to create CGImage from kernel output")
            return nil
        }

        let finalSize = NSSize(width: ciImage.extent.width, height: ciImage.extent.height)
        return NSImage(cgImage: cgImage, size: finalSize)
    }
    
    /// Ease-out cubic function for smooth animation
    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let t1 = t - 1
        return t1 * t1 * t1 + 1
    }
    
    /// Clean up resources
    func cleanup() {
        window.close()
    }
}

// StreamOutputHandler removed - using one-shot capture instead

/**
 * LogFileViewer - Tails /tmp/mousetrail.log and provides colored, chunked display.
 * Reads the last chunk of the file on open and polls for new lines.
 */
@Observable
class LogFileViewer {
    static let shared = LogFileViewer()

    static let logPath = "/tmp/mousetrail.log"
    static let restartMarker = "━━━ MouseTrail started"
    private static let tailBytes = 32_768  // Read last 32KB on initial load

    struct LogLine: Identifiable {
        let id: Int
        let text: String
        let kind: Kind

        enum Kind {
            case info
            case debug
            case error
            case restart
        }
    }

    var lines: [LogLine] = []
    private var fileOffset: UInt64 = 0
    private var nextID = 0
    private var pollTimer: Timer?

    private init() {}

    /// Write a restart separator to the log file, then load the tail.
    func start() {
        writeRestartMarker()
        loadTail()
        startPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Load the last chunk of the log file.
    func loadTail() {
        guard let handle = FileHandle(forReadingAtPath: Self.logPath) else { return }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readStart: UInt64 = fileSize > UInt64(Self.tailBytes) ? fileSize - UInt64(Self.tailBytes) : 0
        handle.seek(toFileOffset: readStart)
        let data = handle.readDataToEndOfFile()
        fileOffset = fileSize

        guard let content = String(data: data, encoding: .utf8) else { return }

        // If we started mid-file, drop the first partial line
        var text = content
        if readStart > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }

        let rawLines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        lines = rawLines.map { makeLine($0) }
    }

    /// Poll for new lines appended since last read.
    func pollNewLines() {
        guard let handle = FileHandle(forReadingAtPath: Self.logPath) else { return }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > fileOffset else {
            if fileSize < fileOffset { fileOffset = 0 }  // File was truncated
            return
        }

        handle.seek(toFileOffset: fileOffset)
        let data = handle.readDataToEndOfFile()
        fileOffset = fileSize

        guard let content = String(data: data, encoding: .utf8) else { return }
        let rawLines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        lines.append(contentsOf: rawLines.map { makeLine($0) })

        // Cap total lines kept in memory
        if lines.count > 2000 {
            lines.removeFirst(lines.count - 2000)
        }
    }

    func clear() {
        lines.removeAll()
        // Truncate the file
        FileManager.default.createFile(atPath: Self.logPath, contents: nil)
        fileOffset = 0
        writeRestartMarker()
    }

    func getAllText() -> String {
        lines.map(\.text).joined(separator: "\n")
    }

    private func writeRestartMarker() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let marker = "\(Self.restartMarker) \(df.string(from: Date())) ━━━\n"
        if let handle = FileHandle(forWritingAtPath: Self.logPath) {
            handle.seekToEndOfFile()
            handle.write(marker.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: Self.logPath, contents: marker.data(using: .utf8))
        }
    }

    private func makeLine(_ text: String) -> LogLine {
        let kind: LogLine.Kind
        if text.contains(Self.restartMarker) {
            kind = .restart
        } else if text.contains("[error]") || text.contains("crash") || text.contains("fatal") {
            kind = .error
        } else if text.contains("[debug]") {
            kind = .debug
        } else {
            kind = .info
        }
        let line = LogLine(id: nextID, text: text, kind: kind)
        nextID += 1
        return line
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollNewLines()
        }
    }
}

// MARK: - Log Levels

enum LogLevel: Int, Comparable, CaseIterable {
    case off = 0
    case info = 1
    case debug = 2

    var label: String {
        switch self {
        case .off: return "Off"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }

    var prefix: String {
        switch self {
        case .off: return ""
        case .info: return "[info]"
        case .debug: return "[debug]"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Current log level — controlled via settings
var currentLogLevel: LogLevel = .info

/// Cached date formatter — avoids per-log allocation.
private let logTimestampFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "HH:mm:ss"
    return df
}()

/// Log at info level — high-level state changes, gesture detections, initialization.
/// @autoclosure lets the caller's string interpolation be skipped entirely when gated out.
func logInfo(_ message: @autoclosure () -> String) {
    guard LogLevel.info <= currentLogLevel else { return }
    writeLog(message(), level: .info)
}

/// Log at debug level — verbose coordinate dumps, rect calculations, capture details.
func logDebug(_ message: @autoclosure () -> String) {
    guard LogLevel.debug <= currentLogLevel else { return }
    writeLog(message(), level: .debug)
}

/// Legacy function — routes to logDebug for backward compatibility
func debugLog(_ message: @autoclosure () -> String) {
    guard LogLevel.debug <= currentLogLevel else { return }
    writeLog(message(), level: .debug)
}

private func writeLog(_ message: String, level: LogLevel) {
    let line = "[\(logTimestampFormatter.string(from: Date()))] \(level.prefix) \(message)"
    print(line)
    let fileLine = line + "\n"
    let logPath = LogFileViewer.logPath
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(fileLine.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: fileLine.data(using: .utf8))
    }
}

/**
 * RippleManager - Manages multiple concurrent ripple effects
 *
 * This class handles creating, updating, and removing ripple effects,
 * as well as coordinating screen capture and animation timing.
 */
class RippleManager: NSObject {
    /// Active ripple effects
    var activeRipples: [RippleEffect] = []

    /// Called when a ripple is added so the animation driver can be restarted
    var onRippleAdded: (() -> Void)?

    /// Settings reference for ripple parameters
    weak var settings: TrailSettings?

    /// Maximum concurrent ripples
    let maxRipples = 10

    /// Has screen recording permission
    var hasPermission = false
    private var isCheckingScreenCapturePermission = false
    private var hasRequestedScreenCapturePermission = false
    
    override init() {
        super.init()
        checkAndSetupScreenCapture()
    }
    
    /// Check for existing permission and setup capture
    func checkAndSetupScreenCapture() {
        guard !isCheckingScreenCapturePermission else { return }
        isCheckingScreenCapturePermission = true
        logInfo("Checking screen capture permission...")
        
        // Test permission by attempting a small capture
        Task { @MainActor in
            defer { self.isCheckingScreenCapturePermission = false }
            do {
                // Try to capture a small area
                let testRect = CGRect(x: 0, y: 0, width: 10, height: 10)
                let _ = try await captureScreenArea(rect: testRect)
                
                // If we got here, we have permission
                logInfo("Test capture succeeded - permission granted")
                self.hasPermission = true
                self.hasRequestedScreenCapturePermission = false
            } catch {
                logInfo("Test capture failed: \(error)")
                
                // Check if it's a permission error (SCStreamError code -3801 or keyword match)
                let nsError = error as NSError
                let isPermissionError = (nsError.code == -3801) ||
                    error.localizedDescription.contains("not authorized") ||
                    error.localizedDescription.contains("permission") ||
                    error.localizedDescription.contains("denied") ||
                    error.localizedDescription.contains("declined")
                if isPermissionError {
                    logInfo("Screen recording permission not granted")
                    self.hasPermission = false
                    
                    // Request permission once and rely on the explicit settings action
                    // to retry later instead of polling in the background forever.
                    if !self.hasRequestedScreenCapturePermission {
                        self.hasRequestedScreenCapturePermission = true
                        CGRequestScreenCaptureAccess()
                    }
                } else {
                    // Some other error - maybe still try to set up
                    logInfo("Non-permission error, attempting setup anyway")
                    self.hasPermission = false
                }
            }
        }
    }
    
    /// Create a new ripple at the specified location
    func createRipple(at location: NSPoint) {
        // Limit concurrent ripples
        if activeRipples.count >= maxRipples {
            return
        }
        
        logInfo("Starting ripple at: \(location)")
        
        // Calculate available space to screen edges
        var minDistanceToEdge: CGFloat = .greatestFiniteMagnitude
        
        // Find all screen bounds and calculate minimum distance to any edge
        for screen in NSScreen.screens {
            let frame = screen.frame
            
            // Calculate distances to each edge
            let distanceToLeft = location.x - frame.minX
            let distanceToRight = frame.maxX - location.x
            let distanceToBottom = location.y - frame.minY
            let distanceToTop = frame.maxY - location.y
            
            // Only consider edges of the screen containing the click point
            if frame.contains(location) {
                minDistanceToEdge = min(minDistanceToEdge, distanceToLeft, distanceToRight, distanceToBottom, distanceToTop)
                debugLog("Click on screen \(frame), distances: L=\(distanceToLeft), R=\(distanceToRight), B=\(distanceToBottom), T=\(distanceToTop)")
            }
        }
        
        debugLog("Minimum distance to edge: \(minDistanceToEdge)")
        
        // Read radius from settings
        let settingsRadius = CGFloat(settings?.rippleRadius ?? 150)
        let radiusBuffer: CGFloat = 50 // Capture should be this much larger than display
        let defaultCaptureRadius = settingsRadius + radiusBuffer

        // Adjust radii based on available space
        let maxRadius: CGFloat
        let captureRadius: CGFloat

        if minDistanceToEdge < defaultCaptureRadius {
            // We're near an edge, need to adjust
            captureRadius = minDistanceToEdge - 5 // Leave 5px safety margin
            maxRadius = max(captureRadius - radiusBuffer, 30) // Ensure minimum size
            debugLog("Adjusted radii for edge: captureRadius=\(captureRadius), maxRadius=\(maxRadius)")
        } else {
            // Use default sizes
            captureRadius = defaultCaptureRadius
            maxRadius = settingsRadius
        }
        
        // Don't create ripple if it would be too small
        if maxRadius < 30 {
            debugLog("Skipping ripple - too close to edge (maxRadius would be \(maxRadius))")
            return
        }
        
        let captureRect = CGRect(
            x: location.x - captureRadius,
            y: location.y - captureRadius,
            width: captureRadius * 2,
            height: captureRadius * 2
        )
        
        // Calculate centers for debugging
        let clickCenter = location
        let captureRectCenter = NSPoint(
            x: captureRect.midX,
            y: captureRect.midY
        )
        
        debugLog("=== CENTER COMPARISON ===")
        debugLog("Click center: \(clickCenter)")
        debugLog("Capture rect center (bottom-left): \(captureRectCenter)")
        debugLog("Capture rect: origin=(\(captureRect.origin.x), \(captureRect.origin.y)) size=(\(captureRect.width) x \(captureRect.height))")
        
        // Snapshot settings at click time
        let rippleSpeed = CGFloat(settings?.rippleSpeed ?? 120)
        let rippleWavelength = CGFloat(settings?.rippleWavelength ?? 25)
        let rippleDamping = CGFloat(settings?.rippleDamping ?? 2.0)
        let rippleAmplitude = CGFloat(settings?.rippleAmplitude ?? 12)
        let rippleDuration = settings?.rippleDuration ?? 1.2
        let rippleSpecular = CGFloat(settings?.rippleSpecularIntensity ?? 0.8)

        // Capture asynchronously
        Task {
            do {
                // Try to capture - this will tell us if we have permission
                guard let capturedImage = try await captureScreenArea(rect: captureRect) else {
                    debugLog("Failed to capture screen for ripple effect - no image returned")
                    return
                }

                logInfo("Successfully captured screen area for ripple")
                debugLog("[debug] Captured image size: \(capturedImage.width)x\(capturedImage.height)")

                // If we got here, we have permission
                if !self.hasPermission {
                    logInfo("Capture succeeded - updating permission status")
                    self.hasPermission = true
                }

                // Create and add ripple effect on main thread
                await MainActor.run {
                    let ripple = RippleEffect(
                        at: location, capturedImage: capturedImage, maxRadius: maxRadius,
                        speed: rippleSpeed, wavelength: rippleWavelength, damping: rippleDamping,
                        amplitude: rippleAmplitude, duration: rippleDuration, specularIntensity: rippleSpecular)
                    self.activeRipples.append(ripple)
                    logInfo("Ripple created and added")
                    self.onRippleAdded?()
                }
            } catch {
                logInfo("Error capturing screen: \(error)")
                logDebug("Error details: \(error.localizedDescription)")
                
                // Update permission status based on error (SCStreamError code -3801 or keyword match)
                let nsError = error as NSError
                let isPermissionError = (nsError.code == -3801) ||
                    error.localizedDescription.contains("not authorized") ||
                    error.localizedDescription.contains("permission") ||
                    error.localizedDescription.contains("declined")
                if isPermissionError {
                    self.hasPermission = false
                    logInfo("Permission denied based on error")
                }
            }
        }
    }
    
    /// Capture screen area using ScreenCaptureKit
    private func captureScreenArea(rect: CGRect) async throws -> CGImage? {
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Calculate virtual desktop bounds
        var virtualDesktopBounds = CGRect.zero
        for screen in NSScreen.screens {
            virtualDesktopBounds = virtualDesktopBounds.union(screen.frame)
        }
        
        // Log all display frames for debugging
        debugLog("=== DISPLAY CONFIGURATION ===")
        debugLog("Virtual desktop bounds: \(virtualDesktopBounds)")
        debugLog("Virtual desktop height: \(virtualDesktopBounds.height)")
        debugLog("Available displays:")
        for (idx, display) in content.displays.enumerated() {
            let frame = display.frame
            debugLog("Display \(idx): origin=(\(frame.origin.x), \(frame.origin.y)) size=(\(frame.width) x \(frame.height))")
            
            // Find corresponding NSScreen
            if let screen = NSScreen.screens.first(where: { 
                abs($0.frame.origin.x - frame.origin.x) < 1 && 
                abs($0.frame.origin.y - frame.origin.y) < 1 
            }) {
                debugLog("  NSScreen frame: \(screen.frame)")
                debugLog("  Is main: \(screen == NSScreen.main)")
            }
        }
        debugLog("Capture rect (global bottom-left): \(rect)")
        
        // Find the display containing the rect
        guard let display = content.displays.first(where: { display in
            display.frame.contains(rect)
        }) else {
            debugLog("No display found for rect: \(rect)")
            // Since we're now pre-calculating bounds, this should rarely happen
            // Just return nil instead of trying to clip
            return nil
        }
        
        // Create a content filter for the display
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Configure for the specific rect
        // ScreenCaptureKit uses a global top-left coordinate system
        
        // First, convert the global bottom-left rect to global top-left
        // In NSScreen coordinates (bottom-left): rect.origin.y is distance from bottom
        // In ScreenCaptureKit (top-left): we need distance from top
        let globalTopLeftY = virtualDesktopBounds.maxY - (rect.origin.y + rect.height)
        
        debugLog("=== COORDINATE CONVERSION ===")
        debugLog("Global rect (bottom-left): \(rect)")
        debugLog("Virtual desktop max Y: \(virtualDesktopBounds.maxY)")
        debugLog("Global top-left Y: \(globalTopLeftY)")
        
        // Convert to display-relative coordinates for ScreenCaptureKit (top-left origin)
        // Use NSScreen frame for Y conversion since click location is in NSScreen coords
        let matchingScreen = NSScreen.screens.first(where: { $0.frame.contains(rect) })
        let nsHeight = matchingScreen?.frame.height ?? display.frame.height
        let nsOriginY = matchingScreen?.frame.origin.y ?? 0.0

        logInfo("NSScreen height: \(nsHeight), SCDisplay height: \(display.frame.height)")

        let displayRelativeX = rect.origin.x - display.frame.origin.x
        let rectYFromScreenBottom = rect.origin.y - nsOriginY
        let displayRelativeY = nsHeight - (rectYFromScreenBottom + rect.height)

        debugLog("=== Y CONVERSION ===")
        debugLog("NSScreen frame: \(matchingScreen?.frame.debugDescription ?? "nil")")
        debugLog("SCDisplay frame: \(display.frame)")
        debugLog("Rect: \(rect), displayRelativeY: \(displayRelativeY)")
        
        let displayRelativeRect = CGRect(
            x: displayRelativeX,
            y: displayRelativeY,
            width: rect.width,
            height: rect.height
        )
        
        debugLog("Display-relative rect: \(displayRelativeRect)")
        
        // Verify the center calculation
        let globalCenter = NSPoint(x: rect.midX, y: rect.midY)
        let displayRelativeCenter = NSPoint(x: displayRelativeRect.midX, y: displayRelativeRect.midY)
        debugLog("Click center (global bottom-left): \(globalCenter)")
        debugLog("Capture center (display-relative): \(displayRelativeCenter)")
        debugLog("Centers should match when properly converted")
        
        let config = SCStreamConfiguration()
        // Ensure the rect dimensions are valid
        if displayRelativeRect.width <= 0 || displayRelativeRect.height <= 0 {
            debugLog("Invalid rect dimensions: \(displayRelativeRect)")
            return nil
        }
        config.sourceRect = displayRelativeRect
        config.width = Int(displayRelativeRect.width)
        config.height = Int(displayRelativeRect.height)
        config.scalesToFit = false
        config.showsCursor = false
        
        // Use SCScreenshotManager for one-shot capture
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        return image
    }
    

    /// Crop a CGImage to a specific rect
    private func cropImage(_ image: CGImage, to rect: CGRect) -> CGImage? {
        // Convert rect to image coordinates
        let imageRect = CGRect(
            x: rect.origin.x,
            y: CGFloat(image.height) - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        
        // Ensure rect is within image bounds
        let clippedRect = imageRect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !clippedRect.isEmpty else { return nil }
        
        return image.cropping(to: clippedRect)
    }
    
    /// Create a placeholder gradient image for ripple effect
    private func createPlaceholderImage(size: CGFloat) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: Int(size),
            height: Int(size),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        // Draw a radial gradient
        let centerX = size / 2
        let centerY = size / 2
        let radius = size / 2
        
        let locations: [CGFloat] = [0.0, 0.3, 0.6, 1.0]
        let colors: [CGFloat] = [
            0.2, 0.4, 0.8, 0.3,  // Center color (blue-ish)
            0.3, 0.5, 0.7, 0.5,  // Mid color
            0.4, 0.6, 0.8, 0.3,  // Mid-outer color
            0.5, 0.7, 0.9, 0.0   // Edge color (transparent)
        ]
        
        guard let gradient = CGGradient(
            colorSpace: colorSpace,
            colorComponents: colors,
            locations: locations,
            count: locations.count
        ) else { return nil }
        
        context.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: centerX, y: centerY),
            startRadius: 0,
            endCenter: CGPoint(x: centerX, y: centerY),
            endRadius: radius,
            options: []
        )
        
        return context.makeImage()
    }
    
    /// Update all active ripples
    func updateRipples() {
        let countBefore = activeRipples.count
        // Update each ripple and remove completed ones
        activeRipples.removeAll { ripple in
            let shouldContinue = ripple.update()
            if !shouldContinue {
                logDebug("Ripple animation complete, cleaning up")
                ripple.cleanup()
                return true // Remove from array
            }
            return false
        }
        if countBefore > 0 && activeRipples.isEmpty {
            logDebug("All ripples cleaned up")
        }
    }
    
    /// Clear all active ripples immediately
    func clearAllRipples() {
        logDebug("Clearing all active ripples")
        for ripple in activeRipples {
            ripple.cleanup()
        }
        activeRipples.removeAll()
    }
    
    /// Clean up all ripples
    func cleanup() {
        for ripple in activeRipples {
            ripple.cleanup()
        }
        activeRipples.removeAll()
    }
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

    /// Global event monitors for mouse movement and clicks
    var eventMonitors: [Any] = []

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

    let springCursorResponse: CGFloat = 16.0
    let springCursorDampingRatio: CGFloat = 1.08
    let springCursorMaxStep: TimeInterval = 1.0 / 240.0
    let springCursorSnapDistance: CGFloat = 240.0
    let springCursorSnapInterval: TimeInterval = 0.15

    /// Raw cursor samples used for delayed, spline-based trail playback.
    var rawMouseSamples: [MouseSample] = []

    /// Monotonic search cursor for the linear smooth-playback experiment.
    var smoothPlaybackSearchIndex = 0

    /// Playback cursor position in the raw-sample timeline.
    var visualPlaybackTime: TimeInterval?

    /// Keep the trail slightly behind the real cursor so we can shape it with future samples.
    let visualPlaybackDelay: TimeInterval = 0.075

    /// Emit synthetic trail points at a higher rate than incoming mouse events.
    let visualPlaybackSampleInterval: TimeInterval = 1.0 / 240.0

    /// Keep enough history to interpolate and fade the trail without unbounded growth.
    let rawMouseSampleHistoryDuration: TimeInterval = 1.5
    
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
        if let movementMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: movementMask,
            handler: { [weak self] event in
                self?.handleMouseMovement(event)
            }
        ) {
            eventMonitors.append(movementMonitor)
        }

        // Monitor mouse clicks for ripple effect in both active and inactive states.
        if let clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown,
            handler: { [weak self] event in
                self?.handleMouseClick(event)
            }
        ) {
            eventMonitors.append(clickMonitor)
        }

        // Monitor left mouse up for click-drag classification
        if let mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseUp,
            handler: { [weak self] event in
                self?.handleMouseUp(event)
            }
        ) {
            eventMonitors.append(mouseUpMonitor)
        }

        // Monitor modifier key changes for hyper+circle release detection
        if let flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in
                self?.handleFlagsChanged(event)
            }
        ) {
            eventMonitors.append(flagsGlobalMonitor)
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
        settings.onChanged = { [weak self] in
            self?.handleTrailSettingsChanged()
        }
        settings.onVisibilityChanged = { [weak self] in
            self?.applyVisibilitySettings()
        }
        settings.onGestureParamsChanged = { [weak self] in
            self?.applyGestureDetectorParams()
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

        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()

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
