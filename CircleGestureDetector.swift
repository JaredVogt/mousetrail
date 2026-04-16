import Foundation

/// Direction of circular motion.
enum CircleDirection: String, Codable {
    case clockwise
    case counterClockwise
}

/// Rich event returned when a circle gesture is detected.
struct CircleEvent {
    /// Direction of the circular motion
    let direction: CircleDirection

    /// Average distance from centroid during the circles
    let averageRadius: CGFloat

    /// Number of full circles completed
    let circleCount: Int

    let timestamp: TimeInterval
}

/// Detects circular mouse gestures by tracking cumulative angular displacement
/// around the centroid of recent mouse positions. Triggers when the required
/// number of full circles are completed within a time window.
/// Returns a CircleEvent with direction and radius information.
struct CircleGestureDetector {
    // MARK: - Configuration

    /// Time window in which completed circles must occur to trigger
    var circleTimeWindow: TimeInterval = 3.0

    /// Maximum age of samples used for centroid and angle computation
    var sampleWindow: TimeInterval = 1.5

    /// Minimum distance from centroid (points) to count angular motion
    var minimumRadius: CGFloat = 30.0

    /// Minimum speed (points/sec) between samples to count
    var minimumSpeed: CGFloat = 200.0

    /// Cooldown period after detection
    var cooldownDuration: TimeInterval = 2.0

    /// Number of full circles required to trigger
    var requiredCircles: Int = 2

    /// Maximum ratio of maxRadius/minRadius during circle accumulation.
    /// Rejects overly wobbly circles / spirals. Default 3.0.
    var maximumRadiusVariance: CGFloat = 3.0

    // MARK: - Internal State

    private var samples: [MouseSample] = []
    private let maxSamples = 256

    /// Cumulative angular displacement for the current circle
    private var cumulativeAngle: Double = 0.0

    /// Previous angle (radians) relative to centroid
    private var previousAngle: Double? = nil

    /// Timestamps of recently completed circles
    private var circleTimestamps: [TimeInterval] = []

    /// Last time the gesture fired (for cooldown)
    private var lastDetectionTimestamp: TimeInterval = 0

    /// Track min/max radius during current circle accumulation for quality check
    private var currentMinRadius: CGFloat = .greatestFiniteMagnitude
    private var currentMaxRadius: CGFloat = 0

    /// Track net angular direction (positive = CCW in standard math coords, but CW on screen since Y is flipped)
    private var netAngleSign: Double = 0

    // MARK: - API

    /// Called on every mouse event. Returns a CircleEvent if the circle gesture was just detected.
    mutating func addSample(_ sample: MouseSample) -> CircleEvent? {
        // Append and prune old samples
        samples.append(sample)
        let cutoff = sample.timestamp - (sampleWindow + 0.25)
        if let firstValid = samples.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstValid > 0 { samples.removeFirst(firstValid) }
        } else {
            samples.removeAll()
            resetAngleTracking()
            return nil
        }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }

        // Cooldown check
        if sample.timestamp - lastDetectionTimestamp < cooldownDuration {
            return nil
        }

        // Need enough samples for a meaningful centroid
        guard samples.count >= 8 else { return nil }

        // Compute centroid of retained samples
        let centroid = computeCentroid()

        // Current angle from centroid
        let dx = Double(sample.location.x - centroid.x)
        let dy = Double(sample.location.y - centroid.y)
        let distance = sqrt(dx * dx + dy * dy)

        // Must be far enough from centroid
        guard distance >= Double(minimumRadius) else {
            resetAngleTracking()
            return nil
        }

        // Track radius bounds for quality check
        let cgDistance = CGFloat(distance)
        currentMinRadius = min(currentMinRadius, cgDistance)
        currentMaxRadius = max(currentMaxRadius, cgDistance)

        // Reject if circle is too wobbly (spiral/oval)
        if currentMinRadius > 0 && currentMaxRadius / currentMinRadius > maximumRadiusVariance {
            resetAngleTracking()
            return nil
        }

        // Check speed from previous sample
        if samples.count >= 2 {
            let prev = samples[samples.count - 2]
            let dt = sample.timestamp - prev.timestamp
            if dt > 0 {
                let sdx = sample.location.x - prev.location.x
                let sdy = sample.location.y - prev.location.y
                let speed = sqrt(sdx * sdx + sdy * sdy) / CGFloat(dt)
                if speed < minimumSpeed {
                    return nil
                }
            }
        }

        let currentAngle = atan2(dy, dx)

        if let prevAngle = previousAngle {
            // Compute delta and normalize to (-pi, pi]
            var delta = currentAngle - prevAngle
            while delta > Double.pi { delta -= 2 * Double.pi }
            while delta < -Double.pi { delta += 2 * Double.pi }

            cumulativeAngle += delta
            netAngleSign += delta
        }

        previousAngle = currentAngle

        // Check for circle completion
        if abs(cumulativeAngle) >= 2 * Double.pi {
            circleTimestamps.append(sample.timestamp)
            cumulativeAngle = 0
            previousAngle = nil
            // Reset radius tracking for next circle
            currentMinRadius = .greatestFiniteMagnitude
            currentMaxRadius = 0

            // Prune old circle timestamps
            circleTimestamps = circleTimestamps.filter { sample.timestamp - $0 <= circleTimeWindow }

            // Check if enough circles completed
            if circleTimestamps.count >= requiredCircles {
                // Determine direction from net angle sign.
                // On macOS, screen Y increases downward, so positive atan2 delta
                // with increasing angle = clockwise visually.
                let direction: CircleDirection = netAngleSign >= 0 ? .clockwise : .counterClockwise
                let avgRadius = (currentMinRadius == .greatestFiniteMagnitude) ? 0 : (currentMinRadius + currentMaxRadius) / 2
                let event = CircleEvent(
                    direction: direction,
                    averageRadius: avgRadius,
                    circleCount: circleTimestamps.count,
                    timestamp: sample.timestamp
                )
                circleTimestamps.removeAll()
                netAngleSign = 0
                lastDetectionTimestamp = sample.timestamp
                return event
            }
        }

        return nil
    }

    /// Reset all state
    mutating func reset() {
        samples.removeAll()
        resetAngleTracking()
        circleTimestamps.removeAll()
        lastDetectionTimestamp = 0
    }

    // MARK: - Private

    private mutating func resetAngleTracking() {
        cumulativeAngle = 0
        previousAngle = nil
        currentMinRadius = .greatestFiniteMagnitude
        currentMaxRadius = 0
        netAngleSign = 0
    }

    private func computeCentroid() -> NSPoint {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for sample in samples {
            sumX += sample.location.x
            sumY += sample.location.y
        }
        let count = CGFloat(samples.count)
        return NSPoint(x: sumX / count, y: sumY / count)
    }
}
