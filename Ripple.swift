import Cocoa
import QuartzCore
import ScreenCaptureKit

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
