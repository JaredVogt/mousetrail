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
import CoreVideo
import CoreMedia
import SwiftUI

// Build timestamp - update this when making changes
let BUILD_TIMESTAMP = "2026-04-09 23:38:30"

/**
 * TrailPoint - Represents a single point in the mouse trail
 */
struct TrailPoint {
    let position: NSPoint
    let timestamp: TimeInterval
    let velocity: CGFloat // Speed in pixels per second
}

/**
 * TrailView - Hardware-accelerated view that renders a smooth mouse trail
 * 
 * Uses CAShapeLayer and Catmull-Rom spline interpolation for smooth curves
 * with glow effects and continuous path rendering.
 */
class TrailView: NSView {
    /// Maximum number of points to keep in trail
    let maxPoints = 30
    let minimumPointDistance: CGFloat = 0.75
    let interpolationAlpha: CGFloat = 0.5
    
    /// Fade time in seconds for red trail
    var fadeTime: TimeInterval = 0.6
    
    /// Fade time for blue trail (faster)
    var blueFadeTime: TimeInterval = 0.35
    
    /// Base and max width for trail
    let baseWidth: CGFloat = 0.5
    var maxWidth: CGFloat = 8.0
    
    /// Blue width multiplier
    var blueWidthMultiplier: CGFloat = 3.5
    
    /// Trail color (bright neon red with slight orange tint)
    var trailColor = NSColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 1.0)
    
    /// Blue trail color
    var blueTrailColor = NSColor(red: 0.1, green: 0.5, blue: 1.0, alpha: 1.0)
    
    /// Blue opacity values
    var blueOuterOpacity: CGFloat = 0.02
    var blueMiddleOpacity: CGFloat = 0.08
    
    /// Points in the trail
    private var points: [TrailPoint] = []
    
    /// Movement threshold tracking
    private var startPosition: NSPoint?
    private var isTrailActive = false
    private var lastMovementTime: TimeInterval = 0
    var movementThreshold: CGFloat = 30.0  // pixels
    var inactivityTimeout: TimeInterval = 0.5  // seconds
    var minimumVelocity: CGFloat = 0.0  // pixels per second (default to 0 for immediate trail)
    
    /// Layers for red glow effect
    private var outerGlowLayer: CAShapeLayer!
    private var middleGlowLayer: CAShapeLayer!
    private var coreLayer: CAShapeLayer!
    private var gradientMaskLayer: CAGradientLayer!
    
    /// Layers for blue overlay effect
    private var blueOuterGlowLayer: CAShapeLayer!
    private var blueMiddleGlowLayer: CAShapeLayer!
    private var blueCoreLayer: CAShapeLayer!
    
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
        outerGlowLayer = CAShapeLayer()
        outerGlowLayer.fillColor = nil
        outerGlowLayer.strokeColor = trailColor.withAlphaComponent(0.08).cgColor
        outerGlowLayer.lineWidth = maxWidth * 3.0
        outerGlowLayer.lineCap = .round
        outerGlowLayer.lineJoin = .round
        outerGlowLayer.shadowColor = trailColor.cgColor
        outerGlowLayer.shadowRadius = 8
        outerGlowLayer.shadowOpacity = 0.2
        outerGlowLayer.shadowOffset = .zero
        outerGlowLayer.frame = bounds
        outerGlowLayer.masksToBounds = false
        outerGlowLayer.shouldRasterize = false
        outerGlowLayer.rasterizationScale = 2.0 // Retina quality
        
        // Middle glow layer
        middleGlowLayer = CAShapeLayer()
        middleGlowLayer.fillColor = nil
        middleGlowLayer.strokeColor = trailColor.withAlphaComponent(0.25).cgColor
        middleGlowLayer.lineWidth = maxWidth * 1.8
        middleGlowLayer.lineCap = .round
        middleGlowLayer.lineJoin = .round
        middleGlowLayer.shadowColor = trailColor.cgColor
        middleGlowLayer.shadowRadius = 3
        middleGlowLayer.shadowOpacity = 0.3
        middleGlowLayer.shadowOffset = .zero
        middleGlowLayer.frame = bounds
        middleGlowLayer.masksToBounds = false
        middleGlowLayer.shouldRasterize = false
        middleGlowLayer.rasterizationScale = 2.0
        
        // Core layer (brightest, thinnest)
        coreLayer = CAShapeLayer()
        coreLayer.fillColor = nil
        coreLayer.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        coreLayer.lineWidth = maxWidth * 0.3
        coreLayer.lineCap = .round
        coreLayer.lineJoin = .round
        coreLayer.shadowColor = NSColor.white.cgColor
        coreLayer.shadowRadius = 1
        coreLayer.shadowOpacity = 0.4
        coreLayer.shadowOffset = .zero
        coreLayer.frame = bounds
        coreLayer.masksToBounds = false
        coreLayer.shouldRasterize = false
        coreLayer.rasterizationScale = 2.0
        
        // Blue outer glow layer (widest overall) - steeper opacity falloff
        blueOuterGlowLayer = CAShapeLayer()
        blueOuterGlowLayer.fillColor = nil
        blueOuterGlowLayer.strokeColor = blueTrailColor.withAlphaComponent(blueOuterOpacity).cgColor
        blueOuterGlowLayer.lineWidth = maxWidth * 3.0 * blueWidthMultiplier
        blueOuterGlowLayer.lineCap = .round
        blueOuterGlowLayer.lineJoin = .round
        blueOuterGlowLayer.shadowColor = blueTrailColor.cgColor
        blueOuterGlowLayer.shadowRadius = 10
        blueOuterGlowLayer.shadowOpacity = 0.1
        blueOuterGlowLayer.shadowOffset = .zero
        blueOuterGlowLayer.frame = bounds
        blueOuterGlowLayer.masksToBounds = false
        blueOuterGlowLayer.shouldRasterize = false
        blueOuterGlowLayer.rasterizationScale = 2.0
        
        // Blue middle glow layer - steeper opacity
        blueMiddleGlowLayer = CAShapeLayer()
        blueMiddleGlowLayer.fillColor = nil
        blueMiddleGlowLayer.strokeColor = blueTrailColor.withAlphaComponent(blueMiddleOpacity).cgColor
        blueMiddleGlowLayer.lineWidth = maxWidth * 1.8 * blueWidthMultiplier
        blueMiddleGlowLayer.lineCap = .round
        blueMiddleGlowLayer.lineJoin = .round
        blueMiddleGlowLayer.shadowColor = blueTrailColor.cgColor
        blueMiddleGlowLayer.shadowRadius = 4
        blueMiddleGlowLayer.shadowOpacity = 0.15
        blueMiddleGlowLayer.shadowOffset = .zero
        blueMiddleGlowLayer.frame = bounds
        blueMiddleGlowLayer.masksToBounds = false
        blueMiddleGlowLayer.shouldRasterize = false
        blueMiddleGlowLayer.rasterizationScale = 2.0
        
        // Blue core layer (bright blue-white)
        blueCoreLayer = CAShapeLayer()
        blueCoreLayer.fillColor = nil
        blueCoreLayer.strokeColor = NSColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.9).cgColor
        blueCoreLayer.lineWidth = maxWidth * 0.4 * blueWidthMultiplier
        blueCoreLayer.lineCap = .round
        blueCoreLayer.lineJoin = .round
        blueCoreLayer.shadowColor = NSColor.white.cgColor
        blueCoreLayer.shadowRadius = 1
        blueCoreLayer.shadowOpacity = 0.3
        blueCoreLayer.shadowOffset = .zero
        blueCoreLayer.frame = bounds
        blueCoreLayer.masksToBounds = false
        blueCoreLayer.shouldRasterize = false
        blueCoreLayer.rasterizationScale = 2.0
        
        // Create container for all trail layers
        let trailContainer = CALayer()
        trailContainer.frame = bounds
        trailContainer.masksToBounds = false
        // Add red layers first (bottom)
        trailContainer.addSublayer(outerGlowLayer)
        trailContainer.addSublayer(middleGlowLayer)
        trailContainer.addSublayer(coreLayer)
        // Add blue layers on top
        trailContainer.addSublayer(blueOuterGlowLayer)
        trailContainer.addSublayer(blueMiddleGlowLayer)
        trailContainer.addSublayer(blueCoreLayer)
        
        // Setup gradient mask for smooth fading
        gradientMaskLayer = CAGradientLayer()
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
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }
    
    override var frame: NSRect {
        didSet {
            // Update all layer frames when view frame changes
            outerGlowLayer?.frame = bounds
            middleGlowLayer?.frame = bounds
            coreLayer?.frame = bounds
            blueOuterGlowLayer?.frame = bounds
            blueMiddleGlowLayer?.frame = bounds
            blueCoreLayer?.frame = bounds
            gradientMaskLayer?.frame = bounds
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

    private func clearTrailLayers(_ layers: [CAShapeLayer]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers {
            layer.path = nil
            layer.shadowPath = nil
        }
        CATransaction.commit()
    }

    private func applyLineWidths(for trailPoints: [TrailPoint], to layers: [CAShapeLayer], isBlue: Bool) {
        let widthMultiplier = isBlue ? blueWidthMultiplier : 1.0

        guard layers.count >= 3 else { return }

        if isBlue {
            layers[0].lineWidth = maxWidth * 3.0 * widthMultiplier
            layers[1].lineWidth = maxWidth * 1.8 * widthMultiplier
            layers[2].lineWidth = maxWidth * 0.3 * widthMultiplier
            return
        }

        let progress = CGFloat(trailPoints.count) / CGFloat(maxPoints)
        let trailWidth = baseWidth + (maxWidth - baseWidth) * progress
        layers[0].lineWidth = trailWidth * 3.0
        layers[1].lineWidth = trailWidth * 1.8
        layers[2].lineWidth = trailWidth * 0.3
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
    func addPoint(_ point: NSPoint, at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
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
    func hasVisiblePoints(at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        return points.contains { now - $0.timestamp < fadeTime }
    }
    
    /// Update layer colors and properties when values change
    func updateLayerProperties() {
        // Update red trail color
        outerGlowLayer?.strokeColor = trailColor.withAlphaComponent(0.08).cgColor
        outerGlowLayer?.shadowColor = trailColor.cgColor
        middleGlowLayer?.strokeColor = trailColor.withAlphaComponent(0.2).cgColor
        middleGlowLayer?.shadowColor = trailColor.cgColor
        coreLayer?.strokeColor = trailColor.withAlphaComponent(0.9).cgColor
        coreLayer?.shadowColor = trailColor.cgColor
        
        // Update blue trail color and opacity
        blueOuterGlowLayer?.strokeColor = blueTrailColor.withAlphaComponent(blueOuterOpacity).cgColor
        blueOuterGlowLayer?.shadowColor = blueTrailColor.cgColor
        blueMiddleGlowLayer?.strokeColor = blueTrailColor.withAlphaComponent(blueMiddleOpacity).cgColor
        blueMiddleGlowLayer?.shadowColor = blueTrailColor.cgColor
        blueCoreLayer?.strokeColor = NSColor(red: 0.7 * blueTrailColor.redComponent, 
                                           green: 0.85 * blueTrailColor.greenComponent, 
                                           blue: blueTrailColor.blueComponent, 
                                           alpha: 0.9).cgColor
    }
    
    /// Update the trail path
    func updateTrail(at now: TimeInterval = Date().timeIntervalSince1970) {
        // Remove old points
        points.removeAll { now - $0.timestamp > fadeTime }

        guard !points.isEmpty else {
            clearTrailLayers([outerGlowLayer, middleGlowLayer, coreLayer])
            clearTrailLayers([blueOuterGlowLayer, blueMiddleGlowLayer, blueCoreLayer])
            return
        }

        // Build red trail
        buildTrailPath(for: points, layers: [outerGlowLayer, middleGlowLayer, coreLayer])

        // Build blue trail with shorter fade
        let bluePoints = points.filter { now - $0.timestamp <= blueFadeTime }
        buildTrailPath(for: bluePoints, layers: [blueOuterGlowLayer, blueMiddleGlowLayer, blueCoreLayer], isBlue: true)
    }
    
    /// Build trail path for given points and layers
    private func buildTrailPath(for trailPoints: [TrailPoint], layers: [CAShapeLayer], isBlue: Bool = false) {
        guard trailPoints.count >= 2 else {
            clearTrailLayers(layers)
            return
        }
        
        // Create single continuous path through all points
        let path = CGMutablePath()
        path.move(to: trailPoints[0].position)

        for i in 0..<(trailPoints.count - 1) {
            let p0 = i > 0 ? trailPoints[i - 1].position : trailPoints[i].position
            let p1 = trailPoints[i].position
            let p2 = trailPoints[i + 1].position
            let p3 = (i + 2 < trailPoints.count) ? trailPoints[i + 2].position : trailPoints[i + 1].position

            let avgVelocity = (trailPoints[i].velocity + trailPoints[i + 1].velocity) / 2.0
            let minSteps = isBlue ? 4 : 5
            let maxSteps = isBlue ? 10 : 14
            let velocityFactor = min(avgVelocity / 1200.0, 1.0)
            let steps = max(1, Int(CGFloat(minSteps) + (CGFloat(maxSteps - minSteps) * velocityFactor)))

            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let point = centripetalCatmullRomPoint(p0, p1, p2, p3, t: t)
                path.addLine(to: point)
            }
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

/**
 * RippleEffect - Represents a single ripple distortion effect
 *
 * This class manages the lifecycle of a ripple effect from click to fade out,
 * including screen capture, distortion animation, and window management.
 */
class RippleEffect {
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
    
    /// Animation duration in seconds
    let animationDuration: TimeInterval = 0.6
    
    init(at location: NSPoint, capturedImage: CGImage, maxRadius: CGFloat) {
        debugLog("Creating RippleEffect at location: \(location)")
        self.clickLocation = location
        self.capturedImage = capturedImage
        self.startTime = Date().timeIntervalSince1970
        self.currentRadius = 0 // Start from center
        self.maxRadius = maxRadius
        
        // Create Core Image context
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false, // Use GPU acceleration
            .cacheIntermediates: true
        ])
        
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
        window.level = .floating + 1 // Above trail
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
        
        // Calculate current radius - starts at 0, expands to maxRadius
        currentRadius = maxRadius * easeOutCubic(progress)
        
        // Calculate distortion intensity - starts high, decreases as ripple expands
        let intensity = (1.0 - progress) * 0.8
        
        // Calculate fade (starts at 0.6 progress)
        let fadeStart: CGFloat = 0.6
        let opacity = progress < fadeStart ? 1.0 : 1.0 - ((progress - fadeStart) / (1.0 - fadeStart))
        
        // Apply distortion filter
        if let distortedImage = applyRippleDistortion(intensity: intensity, progress: progress) {
            debugLog("[debug] Setting distorted image to imageView")
            
            // Debug: Check if the image view settings might be causing the issue
            imageView.imageScaling = .scaleNone
            imageView.alphaValue = 1.0
            imageView.wantsLayer = true
            imageView.layer?.backgroundColor = NSColor.clear.cgColor
            
            // Set the distorted image
            imageView.image = distortedImage
            containerView.alphaValue = opacity
            
            debugLog("[debug] Image set with opacity: \(opacity)")
        } else {
            debugLog("[debug] No distorted image returned!")
            // Try to show the original captured image as fallback
            let fallbackImage = NSImage(cgImage: capturedImage, size: NSSize(width: capturedImage.width, height: capturedImage.height))
            imageView.image = fallbackImage
            containerView.alphaValue = opacity * 0.5 // Make it semi-transparent to debug
        }
        
        return true
    }
    
    /// Apply ripple distortion to captured image
    private func applyRippleDistortion(intensity: CGFloat, progress: CGFloat) -> NSImage? {
        let ciImage = CIImage(cgImage: capturedImage)
        
        debugLog("[debug] Applying ripple distortion - progress: \(progress), intensity: \(intensity)")
        debugLog("[debug] Image extent: \(ciImage.extent)")
        
        // Calculate the center point in the captured image
        let imageCenter = CGPoint(
            x: ciImage.extent.width / 2,
            y: ciImage.extent.height / 2
        )
        
        // Create multiple waves
        var distortedImage = ciImage
        
        // Number of waves and their properties
        let waveCount = 4
        let waveSpacing: CGFloat = 25.0 // Distance between wave peaks
        let waveSpeed: CGFloat = 150.0 // Pixels per second
        
        // Apply multiple wave distortions
        for waveIndex in 0..<waveCount {
            let waveOffset = CGFloat(waveIndex) * waveSpacing
            let waveRadius = (progress * waveSpeed) - waveOffset
            
            // Only process waves that are well within the visible bounds
            // Stop waves at 80% of maxRadius to ensure edge is never exposed
            let maxWaveRadius = maxRadius * 0.8
            
            if waveRadius > 0 && waveRadius < maxWaveRadius {
                // Calculate wave intensity (decreases with distance)
                // More aggressive fade-out as it approaches the edge
                let waveProgress = waveRadius / maxWaveRadius
                let fadeMultiplier = 1.0 - pow(waveProgress, 2.0) // Quadratic fade
                let waveIntensity = intensity * fadeMultiplier * 0.5
                
                debugLog("[debug] Wave \(waveIndex): radius=\(waveRadius), intensity=\(waveIntensity)")
                
                // Create wave distortion using radial gradient distortion
                if let waveDistortion = createWaveDistortion(
                    image: distortedImage,
                    center: imageCenter,
                    radius: waveRadius,
                    intensity: waveIntensity,
                    waveIndex: waveIndex
                ) {
                    distortedImage = waveDistortion
                }
            }
        }
        
        // Apply edge blending mask
        guard let maskedImage = applyEdgeBlending(to: distortedImage, center: imageCenter) else {
            debugLog("[debug] Failed to apply edge blending")
            return nil
        }
        debugLog("[debug] Edge blending applied")
        
        // Skip emboss effect to avoid negative/inverted appearance
        // Just use the masked image directly
        let finalImage = maskedImage
        debugLog("[debug] Skipping emboss effect to avoid inversion")
        
        // Create the final image at the correct size with proper color space
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgImage = ciContext.createCGImage(finalImage, from: ciImage.extent, format: .RGBA8, colorSpace: colorSpace) else {
            debugLog("[debug] Failed to create CGImage from CIImage")
            return nil
        }
        
        // Return image at actual size without any scaling
        let finalSize = NSSize(width: ciImage.extent.width, height: ciImage.extent.height)
        debugLog("[debug] Created final image with size: \(finalSize)")
        return NSImage(cgImage: cgImage, size: finalSize)
    }
    
    /// Create a single wave distortion
    private func createWaveDistortion(image: CIImage, center: CGPoint, radius: CGFloat, intensity: CGFloat, waveIndex: Int) -> CIImage? {
        // Create a more pronounced wave using displacement
        
        // First create a radial gradient for the wave
        let gradientFilter = CIFilter(name: "CIRadialGradient")!
        gradientFilter.setValue(CIVector(x: center.x, y: center.y), forKey: kCIInputCenterKey)
        
        // Create a ring by using two gradients
        let innerRadius = max(0, radius - 15)
        let outerRadius = radius + 15
        
        gradientFilter.setValue(innerRadius, forKey: "inputRadius0")
        gradientFilter.setValue(outerRadius, forKey: "inputRadius1")
        gradientFilter.setValue(CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0), forKey: "inputColor0")
        gradientFilter.setValue(CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1), forKey: "inputColor1")
        
        guard let gradientMask = gradientFilter.outputImage else {
            return nil
        }
        
        // Create displacement map using the gradient
        let displacementFilter = CIFilter(name: "CIDisplacementDistortion")!
        displacementFilter.setValue(image, forKey: kCIInputImageKey)
        displacementFilter.setValue(gradientMask.cropped(to: image.extent), forKey: "inputDisplacementImage")
        displacementFilter.setValue(intensity * 20.0, forKey: kCIInputScaleKey) // Increased scale for more visible effect
        
        return displacementFilter.outputImage
    }
    
    /// Apply edge blending to create smooth edges
    private func applyEdgeBlending(to image: CIImage, center: CGPoint) -> CIImage? {
        // Create a radial gradient mask
        let gradientFilter = CIFilter(name: "CIRadialGradient")!
        gradientFilter.setValue(CIVector(x: center.x, y: center.y), forKey: kCIInputCenterKey)
        gradientFilter.setValue(maxRadius * 0.5, forKey: "inputRadius0") // Inner radius (full opacity) - start fade earlier
        gradientFilter.setValue(maxRadius * 0.9, forKey: "inputRadius1") // Outer radius (transparent) - complete fade before edge
        gradientFilter.setValue(CIColor.white, forKey: "inputColor0")
        gradientFilter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")
        
        guard let gradientMask = gradientFilter.outputImage else {
            return nil
        }
        
        // Apply the mask to the image using blend
        let blendFilter = CIFilter(name: "CIBlendWithMask")!
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage(color: CIColor.clear).cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(gradientMask.cropped(to: image.extent), forKey: kCIInputMaskImageKey)
        
        return blendFilter.outputImage
    }
    
    /// Apply emboss effect for better visibility on solid backgrounds
    private func applyEmbossEffect(to image: CIImage, intensity: CGFloat) -> CIImage? {
        // Create emboss effect using convolution
        let embossFilter = CIFilter(name: "CIConvolution3X3")!
        embossFilter.setValue(image, forKey: kCIInputImageKey)
        
        // 3x3 convolution matrix for emboss effect
        let weights: [CGFloat] = [
            -2, -1,  0,
            -1,  1,  1,
             0,  1,  2
        ]
        embossFilter.setValue(CIVector(values: weights, count: 9), forKey: "inputWeights")
        embossFilter.setValue(1.0, forKey: kCIInputBiasKey)
        
        guard let embossed = embossFilter.outputImage else {
            return image
        }
        
        // Blend embossed with original
        let blendFilter = CIFilter(name: "CISourceOverCompositing")!
        blendFilter.setValue(embossed, forKey: kCIInputImageKey)
        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        guard let blended = blendFilter.outputImage else {
            return image
        }
        
        // Adjust exposure for subtle highlight
        let exposureFilter = CIFilter(name: "CIExposureAdjust")!
        exposureFilter.setValue(blended, forKey: kCIInputImageKey)
        exposureFilter.setValue(intensity * 0.3, forKey: kCIInputEVKey)
        
        return exposureFilter.outputImage ?? image
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
 * DebugLogger - Captures debug messages for display in the app
 */
class DebugLogger {
    static let shared = DebugLogger()
    
    private var messages: [String] = []
    private let maxMessages = 500
    private let dateFormatter: DateFormatter
    
    weak var textView: NSTextView?
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
    }
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        
        DispatchQueue.main.async { [weak self] in
            self?.messages.append(logMessage)
            
            // Keep only recent messages
            if self?.messages.count ?? 0 > self?.maxMessages ?? 500 {
                self?.messages.removeFirst()
            }
            
            // Update text view if connected
            self?.updateTextView()
        }
    }
    
    func clear() {
        messages.removeAll()
        updateTextView()
    }
    
    func getAllMessages() -> String {
        return messages.joined(separator: "\n")
    }
    
    private func updateTextView() {
        guard let textView = textView else { return }
        textView.string = messages.joined(separator: "\n")
        
        // Scroll to bottom
        if let textStorage = textView.textStorage {
            textView.scrollRangeToVisible(NSRange(location: textStorage.length, length: 0))
        }
    }
}

// Global function to replace print for debug messages
func debugLog(_ message: String) {
    print("[debug] \(message)")  // Still print to console
    DebugLogger.shared.log(message)  // Also log to our debug window
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
    
    /// Maximum concurrent ripples
    let maxRipples = 10
    
    /// Has screen recording permission
    var hasPermission = false
    
    override init() {
        super.init()
        checkAndSetupScreenCapture()
    }
    
    /// Check for existing permission and setup capture
    func checkAndSetupScreenCapture() {
        debugLog("Checking screen capture permission...")
        
        // Test permission by attempting a small capture
        Task { @MainActor in
            do {
                // Try to capture a small area
                let testRect = CGRect(x: 0, y: 0, width: 10, height: 10)
                let _ = try await captureScreenArea(rect: testRect)
                
                // If we got here, we have permission
                debugLog("Test capture succeeded - permission granted")
                self.hasPermission = true
            } catch {
                debugLog("Test capture failed: \(error)")
                
                // Check if it's a permission error
                if error.localizedDescription.contains("not authorized") || 
                   error.localizedDescription.contains("permission") ||
                   error.localizedDescription.contains("denied") {
                    debugLog("Screen recording permission not granted")
                    
                    // Request permission
                    CGRequestScreenCaptureAccess()
                    
                    // Try again after delay - use Task to avoid Sendable warning
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        self.checkAndSetupScreenCapture()
                    }
                } else {
                    // Some other error - maybe still try to set up
                    debugLog("Non-permission error, attempting setup anyway")
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
        
        debugLog("Starting ripple creation at location (bottom-left): \(location)")
        
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
        
        // Default sizes
        let defaultMaxRadius: CGFloat = 150
        let defaultCaptureRadius: CGFloat = 200
        let radiusBuffer: CGFloat = 50 // Capture should be this much larger than display
        
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
            maxRadius = defaultMaxRadius
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
        
        // Capture asynchronously
        Task {
            do {
                // Try to capture - this will tell us if we have permission
                guard let capturedImage = try await captureScreenArea(rect: captureRect) else {
                    debugLog("Failed to capture screen for ripple effect - no image returned")
                    return
                }
                
                debugLog("Successfully captured screen area for ripple")
                debugLog("[debug] Captured image size: \(capturedImage.width)x\(capturedImage.height)")
                
                // If we got here, we have permission
                if !self.hasPermission {
                    debugLog("Capture succeeded - updating permission status")
                    self.hasPermission = true
                }
                
                // Create and add ripple effect on main thread
                await MainActor.run {
                    let ripple = RippleEffect(at: location, capturedImage: capturedImage, maxRadius: maxRadius)
                    self.activeRipples.append(ripple)
                    debugLog("Ripple created and added")
                }
            } catch {
                debugLog("Error capturing screen: \(error)")
                debugLog("Error details: \(error.localizedDescription)")
                
                // Update permission status based on error
                if error.localizedDescription.contains("not authorized") || 
                   error.localizedDescription.contains("permission") {
                    self.hasPermission = false
                    debugLog("Permission denied based on error")
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
        
        // Now convert to display-relative coordinates
        let displayRelativeX = rect.origin.x - display.frame.origin.x
        
        // For Y coordinate conversion:
        // ScreenCaptureKit uses top-left origin (Y=0 at top)
        // NSScreen uses bottom-left origin (Y=0 at bottom)
        
        // First, get the rect position relative to the display
        let rectYFromDisplayBottom = rect.origin.y - display.frame.origin.y
        
        // Then flip to top-left coordinates
        // The rect's bottom edge is at rectYFromDisplayBottom
        // So the rect's top edge (in top-left coords) is:
        var displayRelativeY = display.frame.height - (rectYFromDisplayBottom + rect.height)
        
        // HACK: If display has Y offset, try using global coordinates
        // This suggests ScreenCaptureKit might handle offset displays differently
        if display.frame.origin.y > 0 {
            debugLog("WARNING: Display has Y offset of \(display.frame.origin.y), trying alternative calculation")
            displayRelativeY = display.frame.height - (rect.origin.y + rect.height)
        }
        
        debugLog("=== DETAILED Y CONVERSION ===")
        debugLog("Display frame: \(display.frame)")
        debugLog("Display Y offset: \(display.frame.origin.y)")
        debugLog("Is this Display 0? \(display.frame.origin.y == 0)")
        debugLog("Click point (global): \(rect.midX), \(rect.midY)")
        debugLog("Rect global: \(rect)")
        debugLog("Rect Y from display bottom: \(rectYFromDisplayBottom)")
        debugLog("Display-relative Y (top-left): \(displayRelativeY)")
        debugLog("Formula: \(display.frame.height) - (\(rectYFromDisplayBottom) + \(rect.height)) = \(displayRelativeY)")
        
        // Let's also test what happens if we ignore the Y offset for Display 1
        if display.frame.origin.y > 0 {
            let alternativeY = display.frame.height - (rect.origin.y + rect.height)
            debugLog("EXPERIMENTAL: What if we use global Y directly? \(alternativeY)")
        }
        
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
        // Update each ripple and remove completed ones
        activeRipples.removeAll { ripple in
            let shouldContinue = ripple.update()
            if !shouldContinue {
                ripple.cleanup()
                return true // Remove from array
            }
            return false
        }
    }
    
    /// Clear all active ripples immediately
    func clearAllRipples() {
        debugLog("Clearing all active ripples")
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
 * SelectiveClickPanel - A custom NSPanel that implements intelligent mouse interaction
 *
 * This panel ignores all mouse events by default, making it click-through for most
 * of its surface. However, it dynamically enables mouse interaction when the cursor
 * hovers over specific areas (like the close button).
 *
 * This pattern is useful for overlay windows that need to be mostly non-intrusive
 * but still provide some interactive elements.
 */
class SelectiveClickPanel: NSPanel {
    /// Reference to the close button for tracking area management
    var closeButton: NSButton?
    
    /// The tracking area that monitors mouse hover over the close button
    var closeButtonTrackingArea: NSTrackingArea?
    
    /// Flag indicating whether the window is in draggable mode (Command key held)
    var isDraggable = false
    
    /**
     * Initializes the panel with custom window behavior
     *
     * We override the style mask to create a borderless, non-activating panel
     * that acts as an overlay. The panel starts with mouse events disabled,
     * making it click-through by default.
     */
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        // Force borderless and non-activating style regardless of input parameters
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: backingStoreType, defer: flag)
        
        // Configure panel properties for overlay behavior
        self.isFloatingPanel = true              // Float above other windows
        self.becomesKeyOnlyIfNeeded = true      // Don't steal keyboard focus
        self.hidesOnDeactivate = false          // Stay visible when app loses focus
        self.ignoresMouseEvents = true          // Start click-through
    }
    
    /**
     * Prevents the window from becoming the key window
     * This ensures the window doesn't steal keyboard focus from other apps
     */
    override var canBecomeKey: Bool {
        return false
    }
    
    /**
     * Prevents the window from becoming the main window
     * This maintains the overlay behavior without interfering with app focus
     */
    override var canBecomeMain: Bool {
        return false
    }
    
    /**
     * Sets up mouse tracking for the close button
     *
     * This creates a tracking area that monitors when the mouse enters/exits
     * the close button area, allowing us to selectively enable mouse interaction
     *
     * - Parameter button: The close button to track
     */
    func setupTrackingArea(for button: NSButton) {
        self.closeButton = button
        updateTrackingArea()
    }
    
    /**
     * Updates the tracking area when the button frame changes
     *
     * This ensures the tracking area always matches the button's current position
     * and size, even if the window is resized or the button is moved
     */
    func updateTrackingArea() {
        // Clean up any existing tracking area
        if let oldArea = closeButtonTrackingArea {
            self.contentView?.removeTrackingArea(oldArea)
        }
        
        // Create new tracking area for the current button position
        if let button = closeButton {
            let trackingArea = NSTrackingArea(
                rect: button.frame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            self.contentView?.addTrackingArea(trackingArea)
            closeButtonTrackingArea = trackingArea
        }
    }
    
    /**
     * Called when mouse enters the tracking area (close button)
     *
     * This enables mouse events for the window, allowing the button to be clicked
     */
    override func mouseEntered(with event: NSEvent) {
        self.ignoresMouseEvents = false
    }
    
    /**
     * Called when mouse exits the tracking area (close button)
     *
     * This disables mouse events again, unless the window is in draggable mode
     * (Command key held), making the window click-through for most of its surface
     */
    override func mouseExited(with event: NSEvent) {
        if !isDraggable {
            self.ignoresMouseEvents = true
        }
    }
}

/**
 * AppDelegate - Main application controller
 *
 * Manages the application lifecycle, creates and maintains both overlay windows,
 * handles global event monitoring, and coordinates all UI updates.
 */
class AppDelegate: NSObject, NSApplicationDelegate {
    /**
     * Application constants organized in a nested enum for clarity
     * These values control the appearance and behavior of the app
     */
    private enum Constants {
        /// Width of the info panel window in points
        static let windowWidth: CGFloat = 400
        
        /// Height of the info panel window in points
        static let windowHeight: CGFloat = 450
        
        /// Font size for the info display text
        static let fontSize: CGFloat = 11
        
        /// Opacity of the info panel background (0.0 = transparent, 1.0 = opaque)
        static let backgroundOpacity: CGFloat = 0.8
        
        /// Update frequency for smooth animation (60 FPS)
        static let updateInterval: TimeInterval = 1.0 / 60.0
    }
    
    // MARK: - Info Panel Properties
    
    /// The main info panel window that displays system information
    var window: SelectiveClickPanel!
    
    /// Text field displaying mouse coordinates and system info
    var label: NSTextField!
    
    /// Container view with the colored border
    var borderView: NSView!
    
    /// Slider controls and their value labels
    var movementThresholdSlider: NSSlider!
    var movementThresholdLabel: NSTextField!
    var minimumVelocitySlider: NSSlider!
    var minimumVelocityLabel: NSTextField!
    var blueWidthSlider: NSSlider!
    var blueWidthLabel: NSTextField!
    var blueOuterOpacitySlider: NSSlider!
    var blueOuterOpacityLabel: NSTextField!
    var blueMiddleOpacitySlider: NSSlider!
    var blueMiddleOpacityLabel: NSTextField!
    var fadeDurationSlider: NSSlider!
    var fadeDurationLabel: NSTextField!
    var blueFadeDurationSlider: NSSlider!
    var blueFadeDurationLabel: NSTextField!
    
    /// Color sliders
    var redColorSlider: NSSlider!
    var redColorLabel: NSTextField!
    var greenColorSlider: NSSlider!
    var greenColorLabel: NSTextField!
    var blueColorSlider: NSSlider!
    var blueColorLabel: NSTextField!
    var blueRedSlider: NSSlider!
    var blueRedLabel: NSTextField!
    var blueGreenSlider: NSSlider!
    var blueGreenLabel: NSTextField!
    var blueBlueSlider: NSSlider!
    var blueBlueLabel: NSTextField!
    
    /// Close button for terminating the application
    var closeButton: NSButton!
    
    // MARK: - Event Monitoring Properties
    
    /// Global event monitor for mouse movement
    var eventMonitor: Any?
    
    /// Global event monitor for keyboard modifier flags
    var flagsMonitor: Any?
    
    /// Timer for smooth UI updates at 60 FPS
    var updateTimer: Timer?
    
    /// Display link for vsync-synchronized updates
    var displayLink: CVDisplayLink?
    
    // MARK: - Menu Bar Properties

    /// Trail settings (shared with SwiftUI MenuBarExtra)
    let settings = TrailSettings()

    /// Toggle states for windows
    var isInfoPanelVisible = false
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
    
    // MARK: - Performance Optimization Properties
    
    /// Motion state for adaptive performance
    enum MotionState {
        case idle
        case active
    }
    
    /// Current motion state
    var motionState: MotionState = .idle
    
    /// Last mouse movement timestamp
    var lastMouseMovement: TimeInterval = 0
    
    /// Idle timeout in seconds
    let idleTimeout: TimeInterval = 0.1
    
    /// Cached frontmost application
    var cachedFrontmostApp: String = "Unknown"
    
    /// Cached screen configuration
    var cachedScreenInfo: String = ""

    /// Latest mouse location received from the global monitor
    var latestMouseLocation: NSPoint = .zero

    /// Whether a new mouse sample needs to be applied on the next animation tick
    var hasPendingMouseSample = false

    private func ensureRippleManager() -> RippleManager {
        if let rippleManager {
            return rippleManager
        }

        let manager = RippleManager()
        rippleManager = manager
        return manager
    }

    private func applyCurrentTrailConfiguration(to trailView: TrailView) {
        trailView.movementThreshold = CGFloat(movementThresholdSlider?.doubleValue ?? 30)
        trailView.minimumVelocity = CGFloat(minimumVelocitySlider?.doubleValue ?? 0)
        trailView.blueWidthMultiplier = CGFloat(blueWidthSlider?.doubleValue ?? 3.5)
        trailView.blueOuterOpacity = CGFloat(blueOuterOpacitySlider?.doubleValue ?? 0.02)
        trailView.blueMiddleOpacity = CGFloat(blueMiddleOpacitySlider?.doubleValue ?? 0.08)
        trailView.fadeTime = fadeDurationSlider?.doubleValue ?? 0.6
        trailView.blueFadeTime = blueFadeDurationSlider?.doubleValue ?? 0.35
        trailView.trailColor = NSColor(
            red: CGFloat(redColorSlider?.doubleValue ?? 1.0),
            green: CGFloat(greenColorSlider?.doubleValue ?? 0.15),
            blue: CGFloat(blueColorSlider?.doubleValue ?? 0.1),
            alpha: 1.0
        )
        trailView.blueTrailColor = NSColor(
            red: CGFloat(blueRedSlider?.doubleValue ?? 0.1),
            green: CGFloat(blueGreenSlider?.doubleValue ?? 0.5),
            blue: CGFloat(blueBlueSlider?.doubleValue ?? 1.0),
            alpha: 1.0
        )
        trailView.updateLayerProperties()
    }

    private func samplePendingMouseMovement(at now: TimeInterval) {
        guard hasPendingMouseSample else { return }

        hasPendingMouseSample = false
        updateTrailPosition(at: latestMouseLocation, timestamp: now)
        updateMouseCoordinates(mouseLocation: latestMouseLocation)
    }

    private func updateTrailAnimation(at now: TimeInterval) {
        for trailView in trailViews {
            trailView.updateTrail(at: now)
        }
    }

    /**
     * Helper method to create a slider with label
     */
    private func createSlider(title: String, min: Double, max: Double, current: Double, y: CGFloat, action: Selector, unit: String = "") -> (slider: NSSlider, label: NSTextField, valueLabel: NSTextField) {
        // Title label
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: 10, y: y, width: 120, height: 20)
        titleLabel.font = .systemFont(ofSize: 10)
        titleLabel.textColor = .white
        
        // Slider
        let slider = NSSlider()
        slider.frame = NSRect(x: 135, y: y, width: 200, height: 20)
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = current
        slider.target = self
        slider.action = action
        slider.isContinuous = true
        
        // Value label
        let valueText = unit.isEmpty ? String(format: "%.2f", current) : String(format: "%.2f%@", current, unit)
        let valueLabel = NSTextField(labelWithString: valueText)
        valueLabel.frame = NSRect(x: 340, y: y, width: 50, height: 20)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = .white
        valueLabel.alignment = .left
        
        borderView.addSubview(titleLabel)
        borderView.addSubview(slider)
        borderView.addSubview(valueLabel)
        
        return (slider, titleLabel, valueLabel)
    }
    
    /**
     * Called when the application has finished launching
     *
     * This is the main entry point where we:
     * 1. Create both overlay windows
     * 2. Set up event monitoring
     * 3. Start the update timer
     * 4. Configure all UI elements
     */
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize debug logging (this won't show yet as UI isn't created)
        print("[debug] MouseTrail starting...")
        
        // Ensure at least one screen is available
        guard NSScreen.screens.first != nil else {
            debugLog("No screens available")
            NSApplication.shared.terminate(self)
            return
        }
        
        // Calculate initial window position centered on current mouse location
        let mouseLocation = NSEvent.mouseLocation
        latestMouseLocation = mouseLocation
        let xPosition = mouseLocation.x - (Constants.windowWidth / 2)
        let yPosition = mouseLocation.y - (Constants.windowHeight / 2)

        // Create the main info panel window
        window = SelectiveClickPanel(
            contentRect: NSRect(x: xPosition,
                                y: yPosition,
                                width: Constants.windowWidth,
                                height: Constants.windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure window transparency and appearance
        window.isOpaque = false                       // Allow transparent regions
        window.backgroundColor = .clear               // Fully transparent background
        window.hasShadow = false                     // No system shadow (we draw our own)
        window.level = .floating                     // Float above normal windows
        
        // Configure window behavior across spaces and Mission Control
        window.collectionBehavior = [
            .canJoinAllSpaces,      // Visible on all desktop spaces
            .ignoresCycle,          // Not included in Command-Tab cycling
            .stationary,            // Not affected by Mission Control
            .fullScreenAuxiliary    // Can appear over full-screen apps
        ]
        window.isMovableByWindowBackground = false    // Require Command key for dragging

        // Set initial window size first so we can calculate positions
        let initialWindowHeight: CGFloat = 900
        window.setContentSize(NSSize(width: 400, height: initialWindowHeight))
        
        // Create container view with visible border
        borderView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: initialWindowHeight))
        borderView.wantsLayer = true
        borderView.layer?.borderColor = NSColor.green.cgColor  // Green in normal state
        borderView.layer?.borderWidth = 3
        borderView.layer?.cornerRadius = 8
        borderView.layer?.backgroundColor = NSColor.black.withAlphaComponent(Constants.backgroundOpacity).cgColor
        borderView.autoresizingMask = [.width, .height]       // Resize with window
        
        label = NSTextField(labelWithString: "")
        // Position label at the top of the window with more height for multiple screens
        label.frame = NSRect(x: 3, y: initialWindowHeight - 120, width: 394, height: 115)
        label.font = .monospacedSystemFont(ofSize: Constants.fontSize, weight: .medium)
        label.textColor = .white
        label.isBordered = false
        label.isEditable = false
        label.alignment = .center
        label.autoresizingMask = [.width, .maxYMargin]
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(Constants.backgroundOpacity).cgColor
        label.layer?.cornerRadius = 5
        label.drawsBackground = false // Don't let NSTextField draw its own background

        // Create close button
        closeButton = NSButton(frame: NSRect(x: 375, y: initialWindowHeight - 25, width: 20, height: 20))
        closeButton.title = "✕"
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.red.withAlphaComponent(0.8).cgColor
        closeButton.layer?.cornerRadius = 10
        closeButton.attributedTitle = NSAttributedString(string: "✕", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .bold)
        ])
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        
        borderView.addSubview(label)
        borderView.addSubview(closeButton) // Add close button after label so it's on top
        
        // Create sliders - starting Y position below the info display
        var currentY: CGFloat = initialWindowHeight - 140
        
        // Movement controls
        let movementSection = createSlider(title: "Movement Threshold:", min: 10, max: 100, current: 30, y: currentY, action: #selector(movementThresholdChanged), unit: "px")
        movementThresholdSlider = movementSection.slider
        movementThresholdLabel = movementSection.valueLabel
        
        currentY -= 25
        let velocitySection = createSlider(title: "Min Velocity:", min: 0, max: 200, current: 0, y: currentY, action: #selector(minimumVelocityChanged), unit: "px/s")
        minimumVelocitySlider = velocitySection.slider
        minimumVelocityLabel = velocitySection.valueLabel
        
        // Blue trail appearance
        currentY -= 30
        let blueWidthSection = createSlider(title: "Blue Width:", min: 0.5, max: 5.0, current: 3.5, y: currentY, action: #selector(blueWidthChanged))
        blueWidthSlider = blueWidthSection.slider
        blueWidthLabel = blueWidthSection.valueLabel
        
        currentY -= 25
        let blueOuterSection = createSlider(title: "Blue Outer Opacity:", min: 0.01, max: 0.1, current: 0.02, y: currentY, action: #selector(blueOuterOpacityChanged))
        blueOuterOpacitySlider = blueOuterSection.slider
        blueOuterOpacityLabel = blueOuterSection.valueLabel
        
        currentY -= 25
        let blueMiddleSection = createSlider(title: "Blue Mid Opacity:", min: 0.05, max: 0.3, current: 0.08, y: currentY, action: #selector(blueMiddleOpacityChanged))
        blueMiddleOpacitySlider = blueMiddleSection.slider
        blueMiddleOpacityLabel = blueMiddleSection.valueLabel
        
        // Fade durations
        currentY -= 30
        let fadeSection = createSlider(title: "Red Fade Time:", min: 0.1, max: 2.0, current: 0.6, y: currentY, action: #selector(fadeDurationChanged), unit: "s")
        fadeDurationSlider = fadeSection.slider
        fadeDurationLabel = fadeSection.valueLabel
        
        currentY -= 25
        let blueFadeSection = createSlider(title: "Blue Fade Time:", min: 0.1, max: 1.0, current: 0.35, y: currentY, action: #selector(blueFadeDurationChanged), unit: "s")
        blueFadeDurationSlider = blueFadeSection.slider
        blueFadeDurationLabel = blueFadeSection.valueLabel
        
        // Red trail color
        currentY -= 30
        let redSection = createSlider(title: "Red Trail - R:", min: 0, max: 1, current: 1.0, y: currentY, action: #selector(redColorChanged))
        redColorSlider = redSection.slider
        redColorLabel = redSection.valueLabel
        
        currentY -= 25
        let greenSection = createSlider(title: "Red Trail - G:", min: 0, max: 1, current: 0.15, y: currentY, action: #selector(redColorChanged))
        greenColorSlider = greenSection.slider
        greenColorLabel = greenSection.valueLabel
        
        currentY -= 25
        let blueSection = createSlider(title: "Red Trail - B:", min: 0, max: 1, current: 0.1, y: currentY, action: #selector(redColorChanged))
        blueColorSlider = blueSection.slider
        blueColorLabel = blueSection.valueLabel
        
        // Blue trail color
        currentY -= 30
        let blueRedSection = createSlider(title: "Blue Trail - R:", min: 0, max: 1, current: 0.1, y: currentY, action: #selector(blueColorChanged))
        blueRedSlider = blueRedSection.slider
        blueRedLabel = blueRedSection.valueLabel
        
        currentY -= 25
        let blueGreenSection = createSlider(title: "Blue Trail - G:", min: 0, max: 1, current: 0.5, y: currentY, action: #selector(blueColorChanged))
        blueGreenSlider = blueGreenSection.slider
        blueGreenLabel = blueGreenSection.valueLabel
        
        currentY -= 25
        let blueBlueSection = createSlider(title: "Blue Trail - B:", min: 0, max: 1, current: 1.0, y: currentY, action: #selector(blueColorChanged))
        blueBlueSlider = blueBlueSection.slider
        blueBlueLabel = blueBlueSection.valueLabel
        
        // Add permission request button
        currentY -= 35
        let permissionButton = NSButton(frame: NSRect(x: 10, y: currentY, width: 380, height: 30))
        permissionButton.title = "Request Screen Recording Permission"
        permissionButton.bezelStyle = .rounded
        permissionButton.target = self
        permissionButton.action = #selector(requestPermissionClicked)
        borderView.addSubview(permissionButton)
        
        // Add debug log section with border
        currentY -= 35
        
        // Create a bordered box for the debug log
        let debugBoxHeight: CGFloat = 200  // Reduced height
        let debugBoxY = currentY - debugBoxHeight
        let debugBox = NSBox(frame: NSRect(x: 10, y: debugBoxY, width: 380, height: debugBoxHeight))
        debugBox.title = "Debug Log"
        debugBox.titlePosition = .atTop
        debugBox.boxType = .primary
        debugBox.borderColor = .gray
        debugBox.fillColor = .clear
        borderView.addSubview(debugBox)
        
        // Add scrollable text view for debug messages inside the box
        let scrollView = NSScrollView(frame: NSRect(x: 5, y: 30, width: 370, height: 140))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.backgroundColor = NSColor.black
        textView.textColor = .green
        textView.autoresizingMask = [.width, .height]
        
        scrollView.documentView = textView
        debugBox.addSubview(scrollView)
        
        // Connect debug logger to text view
        DebugLogger.shared.textView = textView
        
        // Add initial message to show it's working
        debugLog("Debug log initialized")
        
        // Add clear log button inside the box
        let clearLogButton = NSButton(frame: NSRect(x: 5, y: 5, width: 100, height: 25))
        clearLogButton.title = "Clear Log"
        clearLogButton.bezelStyle = .rounded
        clearLogButton.target = self
        clearLogButton.action = #selector(clearDebugLog)
        debugBox.addSubview(clearLogButton)
        
        // Add copy log button
        let copyLogButton = NSButton(frame: NSRect(x: 110, y: 5, width: 100, height: 25))
        copyLogButton.title = "Copy Log"
        copyLogButton.bezelStyle = .rounded
        copyLogButton.target = self
        copyLogButton.action = #selector(copyDebugLog)
        debugBox.addSubview(copyLogButton)
        
        currentY -= debugBoxHeight + 10
        
        // Don't resize window here - we already set it at the beginning
        
        window.contentView?.addSubview(borderView)
        
        // Setup tracking area for close button
        window.setupTrackingArea(for: closeButton)
        
        // Only show window if it should be visible
        if isInfoPanelVisible {
            window.makeKeyAndOrderFront(nil)
        }

        // Wire settings callbacks
        settings.restore()
        isTrailVisible = settings.isTrailVisible
        isInfoPanelVisible = settings.isInfoPanelVisible
        isRippleEnabled = settings.isRippleEnabled
        settings.onChanged = { [weak self] in
            self?.applySettingsToTrailViews()
        }
        settings.onVisibilityChanged = { [weak self] in
            self?.applyVisibilitySettings()
        }
        
        // Create trail windows for each screen
        createTrailWindows()
        
        // Log that app is ready
        debugLog("MouseTrail initialized successfully")
        debugLog("Trail windows created: \(trailWindows.count)")
        debugLog("Monitoring mouse events...")

        // Cache initial system state
        updateCachedSystemInfo()
        
        // Initial display update
        updateDisplay()
        
        // MARK: Event Monitoring Setup
        
        // Monitor global mouse movement
        // Note: Uses weak self to prevent retain cycles
        // Global monitors receive events from all applications, not just ours
        // No special permissions required for mouse movement monitoring
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMovement()
        }
        
        // Monitor global keyboard modifier changes (Command, Option, etc.)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        // Monitor global mouse clicks for ripple effect
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseClick(event)
        }
        
        // Also add local monitor for when our app has focus
        // Global monitors don't receive events when the app is active
        // Local monitors only receive events when our app is active
        // Must return the event to allow normal processing
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event  // Must return event for it to be processed normally
        }
        
        // Don't start the timer - wait for mouse movement
        // This ensures zero CPU usage when idle
        
        // Monitor app switching for immediate UI updates
        // NSWorkspace notifications tell us about app-level changes
        // This specific notification fires when user switches between applications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Monitor screen configuration changes (monitors added/removed)
        // This notification fires when:
        // - A display is connected or disconnected
        // - Display resolution changes
        // - Display arrangement changes in System Preferences
        // - Display mirroring is enabled/disabled
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    /**
     * Handles mouse click events for ripple effect
     */
    func handleMouseClick(_ event: NSEvent) {
        // Check if ripple is enabled
        guard isRippleEnabled else { return }
        
        let clickLocation = NSEvent.mouseLocation
        debugLog("Mouse clicked at: \(clickLocation)")
        
        // Pass the original bottom-left coordinates to createRipple
        // The ripple window uses NSWindow which expects bottom-left coordinates
        ensureRippleManager().createRipple(at: clickLocation)
        
        // Ensure timer is running for ripple animation
        if motionState == .idle {
            transitionToActiveState()
        }
    }
    
    /**
     * Handles mouse movement events with motion detection
     */
    func handleMouseMovement() {
        let now = Date().timeIntervalSince1970
        lastMouseMovement = now
        latestMouseLocation = NSEvent.mouseLocation
        hasPendingMouseSample = true
        
        // Transition to active state if we were idle
        if motionState == .idle {
            transitionToActiveState()
            samplePendingMouseMovement(at: now)
            updateTrailAnimation(at: now)
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
     * Sets up CVDisplayLink for smooth vsync-synchronized animation
     */
    func setupDisplayLink() {
        // Stop any existing timer
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Use 60Hz timer to match typical display refresh rate
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateActiveAnimation()
        }
        
        // Set timer to high precision mode
        if let timer = updateTimer {
            timer.tolerance = 0.001 // Small tolerance for smoothness
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    /**
     * Transition from active to idle state
     */
    func transitionToIdleState() {
        guard motionState == .active else { return }
        let now = Date().timeIntervalSince1970
        
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
        
        // Stop the update timer to save CPU
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    /**
     * Update only during active animation (called by timer)
     */
    func updateActiveAnimation() {
        let now = Date().timeIntervalSince1970
        samplePendingMouseMovement(at: now)
        updateTrailAnimation(at: now)

        // Update ripple animations
        rippleManager?.updateRipples()

        if now - lastMouseMovement >= idleTimeout {
            transitionToIdleState()
        }
    }
    
    /**
     * Updates only the mouse coordinates in the display
     */
    func updateMouseCoordinates(mouseLocation: NSPoint? = nil, force: Bool = false) {
        guard force || isInfoPanelVisible else { return }
        let mouseLocation = mouseLocation ?? latestMouseLocation
        
        // Build display text with cached values - keep rounding for display only
        var displayText = "Build: \(BUILD_TIMESTAMP)\n"
        displayText += "Mouse: x:\(Int(mouseLocation.x)) y:\(Int(mouseLocation.y))\n"
        displayText += "Active: \(cachedFrontmostApp)\n"
        
        // Add screen recording permission status
        let permissionStatus = rippleManager?.hasPermission ?? false
        displayText += "Screen Recording: \(permissionStatus ? "✓ Granted" : "✗ Denied")\n"
        
        displayText += cachedScreenInfo
        
        label.stringValue = displayText.trimmingCharacters(in: .newlines)
    }
    
    /**
     * Updates cached system information
     */
    func updateCachedSystemInfo() {
        // Cache frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            cachedFrontmostApp = frontApp.localizedName ?? "Unknown"
        }
        
        // Cache screen information
        let screens = NSScreen.screens
        var screenText = "Screens: \(screens.count)\n"
        for (index, screen) in screens.enumerated() {
            let resolution = screen.frame.size
            let isMain = screen == NSScreen.main ? " (main)" : ""
            screenText += "[\(index+1)] \(Int(resolution.width))×\(Int(resolution.height))\(isMain)"
            if index < screens.count - 1 {
                screenText += "\n"
            }
        }
        cachedScreenInfo = screenText
    }
    
    /**
     * Updates the information display with current system state
     *
     * This method is called:
     * - By the timer (60 times per second)
     * - When mouse moves
     * - When active application changes
     *
     * It gathers and formats:
     * - Current mouse coordinates
     * - Active application name
     * - Connected display information
     */
    func updateDisplay() {
        updateMouseCoordinates(force: true)
    }
    
    /**
     * Handles keyboard modifier flag changes (Command, Option, Shift, etc.)
     *
     * This method enables/disables window dragging based on the Command key state.
     * When Command is held, the window becomes draggable and the border turns yellow
     * as visual feedback.
     *
     * - Parameter event: The flags changed event containing modifier key states
     */
    func handleFlagsChanged(_ event: NSEvent) {
        let commandKeyPressed = event.modifierFlags.contains(.command)
        
        // Only update if state actually changed to avoid unnecessary work
        if commandKeyPressed != window.isDraggable {
            window.isDraggable = commandKeyPressed
            window.isMovableByWindowBackground = commandKeyPressed
            
            // Toggle mouse event handling based on drag mode
            window.ignoresMouseEvents = !commandKeyPressed
            
            // Provide visual feedback for drag mode
            if commandKeyPressed {
                // Yellow border indicates draggable state
                borderView.layer?.borderColor = NSColor.systemYellow.cgColor
                borderView.layer?.borderWidth = 4
            } else {
                // Green border for normal state
                borderView.layer?.borderColor = NSColor.green.cgColor
                borderView.layer?.borderWidth = 3
            }
        }
    }
    
    /**
     * Handler for close button clicks
     * Terminates the application when the user clicks the × button
     */
    @objc func closeButtonClicked() {
        // Hide the panel instead of terminating
        window.orderOut(nil)
        isInfoPanelVisible = false
        settings.isInfoPanelVisible = false
    }
    
    /**
     * Handler for permission request button
     */
    @objc func requestPermissionClicked() {
        debugLog("Manual permission request triggered")
        
        // First check current status
        let currentStatus = CGPreflightScreenCaptureAccess()
        debugLog("Current permission status: \(currentStatus)")
        
        // Always re-check with actual capture test
        let rippleManager = ensureRippleManager()
        rippleManager.checkAndSetupScreenCapture()
        
        if !currentStatus {
            // Request permission
            CGRequestScreenCaptureAccess()
            debugLog("Permission requested, opening System Settings")
            
            // Open System Settings to Screen Recording
            // Try multiple URL formats as they vary between macOS versions
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
            
            // Check again after delay using actual capture test
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                debugLog("Re-checking permission after manual request")
                self?.rippleManager?.checkAndSetupScreenCapture()
            }
        }
    }
    
    /**
     * Clear the debug log
     */
    @objc func clearDebugLog() {
        DebugLogger.shared.clear()
        debugLog("Debug log cleared")
    }
    
    /**
     * Copy the debug log to clipboard
     */
    @objc func copyDebugLog() {
        let logContent = DebugLogger.shared.getAllMessages()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logContent, forType: .string)
        debugLog("Debug log copied to clipboard")
    }
    
    // MARK: - Slider Actions
    
    @objc private func movementThresholdChanged(_ sender: NSSlider) {
        settings.movementThreshold = sender.doubleValue
    }

    @objc private func minimumVelocityChanged(_ sender: NSSlider) {
        settings.minimumVelocity = sender.doubleValue
    }

    @objc private func blueWidthChanged(_ sender: NSSlider) {
        settings.blueWidthMultiplier = sender.doubleValue
    }

    @objc private func blueOuterOpacityChanged(_ sender: NSSlider) {
        settings.blueOuterOpacity = sender.doubleValue
    }

    @objc private func blueMiddleOpacityChanged(_ sender: NSSlider) {
        settings.blueMiddleOpacity = sender.doubleValue
    }

    @objc private func fadeDurationChanged(_ sender: NSSlider) {
        settings.redFadeTime = sender.doubleValue
    }

    @objc private func blueFadeDurationChanged(_ sender: NSSlider) {
        settings.blueFadeTime = sender.doubleValue
    }

    @objc private func redColorChanged(_ sender: NSSlider) {
        settings.redTrailR = redColorSlider.doubleValue
        settings.redTrailG = greenColorSlider.doubleValue
        settings.redTrailB = blueColorSlider.doubleValue
    }

    @objc private func blueColorChanged(_ sender: NSSlider) {
        settings.blueTrailR = blueRedSlider.doubleValue
        settings.blueTrailG = blueGreenSlider.doubleValue
        settings.blueTrailB = blueBlueSlider.doubleValue
    }
    
    /**
     * Handler for application switching notifications
     * Updates the display immediately when the user switches apps
     * to show the new active application name
     */
    @objc func activeApplicationChanged(_ notification: Notification) {
        // Update cached app name
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            cachedFrontmostApp = frontApp.localizedName ?? "Unknown"
        }
        updateMouseCoordinates(force: isInfoPanelVisible)
    }
    
    /**
     * Called when screen configuration changes (monitors added/removed)
     * Recreates trail windows to match new screen configuration
     *
     * This handler is triggered by NSApplication.didChangeScreenParametersNotification
     * and ensures the trail appears correctly on all connected displays without
     * requiring an app restart.
     *
     * - Parameter notification: The notification containing screen change information
     */
    @objc func screenConfigurationChanged(_ notification: Notification) {
        // Recreate trail windows for new screen configuration
        // This handles monitors being added or removed dynamically
        createTrailWindows()
        
        // Update cached screen info
        updateCachedSystemInfo()
        updateMouseCoordinates(force: isInfoPanelVisible)
    }
    
    /// Apply current settings to all TrailView instances
    func applySettingsToTrailViews() {
        for trailView in trailViews {
            trailView.maxWidth = CGFloat(settings.maxWidth)
            trailView.movementThreshold = CGFloat(settings.movementThreshold)
            trailView.minimumVelocity = CGFloat(settings.minimumVelocity)
            trailView.blueWidthMultiplier = CGFloat(settings.blueWidthMultiplier)
            trailView.blueOuterOpacity = CGFloat(settings.blueOuterOpacity)
            trailView.blueMiddleOpacity = CGFloat(settings.blueMiddleOpacity)
            trailView.fadeTime = settings.redFadeTime
            trailView.blueFadeTime = settings.blueFadeTime
            trailView.trailColor = settings.redTrailNSColor
            trailView.blueTrailColor = settings.blueTrailNSColor
            trailView.updateLayerProperties()
        }

        // Sync info panel sliders if they exist
        movementThresholdSlider?.doubleValue = settings.movementThreshold
        movementThresholdLabel?.stringValue = String(format: "%.0fpx", settings.movementThreshold)
        minimumVelocitySlider?.doubleValue = settings.minimumVelocity
        minimumVelocityLabel?.stringValue = String(format: "%.0fpx/s", settings.minimumVelocity)
        blueWidthSlider?.doubleValue = settings.blueWidthMultiplier
        blueWidthLabel?.stringValue = String(format: "%.2f", settings.blueWidthMultiplier)
        blueOuterOpacitySlider?.doubleValue = settings.blueOuterOpacity
        blueOuterOpacityLabel?.stringValue = String(format: "%.3f", settings.blueOuterOpacity)
        blueMiddleOpacitySlider?.doubleValue = settings.blueMiddleOpacity
        blueMiddleOpacityLabel?.stringValue = String(format: "%.3f", settings.blueMiddleOpacity)
        fadeDurationSlider?.doubleValue = settings.redFadeTime
        fadeDurationLabel?.stringValue = String(format: "%.2fs", settings.redFadeTime)
        blueFadeDurationSlider?.doubleValue = settings.blueFadeTime
        blueFadeDurationLabel?.stringValue = String(format: "%.2fs", settings.blueFadeTime)
        redColorSlider?.doubleValue = settings.redTrailR
        redColorLabel?.stringValue = String(format: "%.2f", settings.redTrailR)
        greenColorSlider?.doubleValue = settings.redTrailG
        greenColorLabel?.stringValue = String(format: "%.2f", settings.redTrailG)
        blueColorSlider?.doubleValue = settings.redTrailB
        blueColorLabel?.stringValue = String(format: "%.2f", settings.redTrailB)
        blueRedSlider?.doubleValue = settings.blueTrailR
        blueRedLabel?.stringValue = String(format: "%.2f", settings.blueTrailR)
        blueGreenSlider?.doubleValue = settings.blueTrailG
        blueGreenLabel?.stringValue = String(format: "%.2f", settings.blueTrailG)
        blueBlueSlider?.doubleValue = settings.blueTrailB
        blueBlueLabel?.stringValue = String(format: "%.2f", settings.blueTrailB)
    }

    /// Apply visibility toggle changes
    func applyVisibilitySettings() {
        // Trail visibility
        if settings.isTrailVisible != isTrailVisible {
            isTrailVisible = settings.isTrailVisible
            for trailWindow in trailWindows {
                if isTrailVisible {
                    trailWindow.makeKeyAndOrderFront(nil)
                } else {
                    trailWindow.orderOut(nil)
                }
            }
        }

        // Info panel visibility
        if settings.isInfoPanelVisible != isInfoPanelVisible {
            isInfoPanelVisible = settings.isInfoPanelVisible
            if isInfoPanelVisible {
                updateMouseCoordinates(force: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderOut(nil)
            }
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
            trailWindow.level = .floating                   // Float above other windows
            
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
            
            // Only show if trails are enabled
            if isTrailVisible {
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
        for trailView in trailViews {
            if trailView.addPoint(screenLocation, at: timestamp) {
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
        // Stop and clean up the update timer
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Remove global event monitors
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        
        // Close and clean up all trail windows
        for window in trailWindows {
            window.close()
        }
        trailWindows.removeAll()
        trailViews.removeAll()
        
        // Clean up ripple effects
        rippleManager?.cleanup()
        
        // Remove notification observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}

