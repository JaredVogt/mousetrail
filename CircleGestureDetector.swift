import Foundation

/// Detects circular mouse gestures by tracking cumulative angular displacement
/// around the centroid of recent mouse positions. Triggers when the required
/// number of full circles are completed within a time window.
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

    // MARK: - API

    /// Called on every mouse event. Returns true if the circle gesture was just detected.
    mutating func addSample(_ sample: MouseSample) -> Bool {
        // Append and prune old samples
        samples.append(sample)
        let cutoff = sample.timestamp - (sampleWindow + 0.25)
        if let firstValid = samples.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstValid > 0 { samples.removeFirst(firstValid) }
        } else {
            samples.removeAll()
            resetAngleTracking()
            return false
        }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }

        // Cooldown check
        if sample.timestamp - lastDetectionTimestamp < cooldownDuration {
            return false
        }

        // Need enough samples for a meaningful centroid
        guard samples.count >= 8 else { return false }

        // Compute centroid of retained samples
        let centroid = computeCentroid()

        // Current angle from centroid
        let dx = Double(sample.location.x - centroid.x)
        let dy = Double(sample.location.y - centroid.y)
        let distance = sqrt(dx * dx + dy * dy)

        // Must be far enough from centroid
        guard distance >= Double(minimumRadius) else {
            resetAngleTracking()
            return false
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
                    return false
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
        }

        previousAngle = currentAngle

        // Check for circle completion
        if abs(cumulativeAngle) >= 2 * Double.pi {
            circleTimestamps.append(sample.timestamp)
            cumulativeAngle = 0
            previousAngle = nil

            // Prune old circle timestamps
            circleTimestamps = circleTimestamps.filter { sample.timestamp - $0 <= circleTimeWindow }

            // Check if enough circles completed
            if circleTimestamps.count >= requiredCircles {
                circleTimestamps.removeAll()
                lastDetectionTimestamp = sample.timestamp
                return true
            }
        }

        return false
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
