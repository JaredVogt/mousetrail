import Cocoa
import QuartzCore

/// Fixed trail-rendering constants — values not exposed through settings.
enum TrailRenderingConfig {
    /// Point count at which trail reaches its full width.
    static let fullWidthPointCount: CGFloat = 40
    /// Centripetal Catmull-Rom alpha.
    static let interpolationAlpha: CGFloat = 0.5
    /// Minimum line width for the core trail at the tail.
    static let baseWidth: CGFloat = 0.5
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
    let fullWidthPointCount: CGFloat = TrailRenderingConfig.fullWidthPointCount
    var minimumPointDistance: CGFloat = 0.5
    var maximumRenderSegmentLength: CGFloat = 6.0
    var renderSmoothingPasses = 2
    let interpolationAlpha: CGFloat = TrailRenderingConfig.interpolationAlpha

    /// Fade time in seconds for core trail
    var fadeTime: TimeInterval = 0.6

    /// Fade time for glow trail (faster)
    var glowFadeTime: TimeInterval = 0.35

    /// Base and max width for trail
    let baseWidth: CGFloat = TrailRenderingConfig.baseWidth
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

    /// Natural shadow opacities — used to restore the look when shadows are
    /// re-enabled after the perf-experiment toggle disables them.
    private static let coreOuterShadowOpacity: Float = 0.2
    private static let coreMiddleShadowOpacity: Float = 0.3
    private static let coreInnerShadowOpacity: Float = 0.4
    private static let glowOuterShadowOpacity: Float = 0.1
    private static let glowMiddleShadowOpacity: Float = 0.15
    private static let glowInnerShadowOpacity: Float = 0.3

    var shadowsEnabled = true {
        didSet { applyShadowOpacities() }
    }

    private func applyShadowOpacities() {
        let m: Float = shadowsEnabled ? 1.0 : 0.0
        coreOuterLayer.shadowOpacity = Self.coreOuterShadowOpacity * m
        coreMiddleLayer.shadowOpacity = Self.coreMiddleShadowOpacity * m
        coreInnerLayer.shadowOpacity = Self.coreInnerShadowOpacity * m
        glowOuterLayer.shadowOpacity = Self.glowOuterShadowOpacity * m
        glowMiddleLayer.shadowOpacity = Self.glowMiddleShadowOpacity * m
        glowInnerLayer.shadowOpacity = Self.glowInnerShadowOpacity * m
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
        coreOuterLayer.shadowOpacity = Self.coreOuterShadowOpacity
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
        coreMiddleLayer.shadowOpacity = Self.coreMiddleShadowOpacity
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
        coreInnerLayer.shadowOpacity = Self.coreInnerShadowOpacity
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
        glowOuterLayer.shadowOpacity = Self.glowOuterShadowOpacity
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
        glowMiddleLayer.shadowOpacity = Self.glowMiddleShadowOpacity
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
        glowInnerLayer.shadowOpacity = Self.glowInnerShadowOpacity
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

        updateLayerVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }

    override var frame: NSRect {
        didSet {
            coreOuterLayer.frame = bounds
            coreMiddleLayer.frame = bounds
            coreInnerLayer.frame = bounds
            glowOuterLayer.frame = bounds
            glowMiddleLayer.frame = bounds
            glowInnerLayer.frame = bounds
            gradientMaskLayer.frame = bounds
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

    /// Add a new point to the trail. `point` is in screen coordinates; trail
    /// points are stored in screen space so they remain correct when the
    /// overlay window moves under them.
    @discardableResult
    func addPoint(_ point: NSPoint, at now: TimeInterval = currentMonotonicTime()) -> Bool {
        if now - lastMovementTime > inactivityTimeout {
            isTrailActive = false
            startPosition = nil
            points.removeAll()
        }

        lastMovementTime = now

        if !isTrailActive {
            if startPosition == nil {
                startPosition = point
                return false
            }

            if let start = startPosition {
                let distance = pointDistance(point, start)

                if distance < movementThreshold {
                    return false
                }

                isTrailActive = true
            }
        }

        var velocity: CGFloat = 0
        var distanceFromLastPoint: CGFloat = 0

        if let lastPoint = points.last {
            let distance = pointDistance(point, lastPoint.position)
            let timeDelta = now - lastPoint.timestamp
            distanceFromLastPoint = distance

            if timeDelta > 0 {
                velocity = distance / CGFloat(timeDelta)
            }
        }

        if distanceFromLastPoint < minimumPointDistance && !points.isEmpty {
            return false
        }

        if velocity < minimumVelocity && !points.isEmpty {
            isTrailActive = false
            startPosition = nil
            points.removeAll()
            return true
        }

        let trailPoint = TrailPoint(position: point, timestamp: now, velocity: velocity)
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
        let positionsScreen = renderPositions(from: trailPoints)

        guard positionsScreen.count >= 2 else {
            clearTrailLayers(layers)
            return
        }

        // Trail points are stored in screen space; translate to view-local now
        // so the path is correct regardless of where the window is positioned.
        let origin = window?.frame.origin ?? .zero
        let renderPositions = positionsScreen.map {
            NSPoint(x: $0.x - origin.x, y: $0.y - origin.y)
        }

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
}
