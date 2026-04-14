import Foundation

/// Detects rapid back-and-forth mouse shaking along any axis.
/// Works by counting direction reversals projected onto the dominant axis of motion.
struct ShakeDetector {
    // MARK: - Configuration

    /// Time window in which reversals must occur to count as a shake
    var timeWindow: TimeInterval = 0.5

    /// Minimum number of direction reversals within the time window to trigger
    var requiredReversals: Int = 3

    /// Minimum distance (points) the mouse must travel between reversals
    var minimumSegmentDisplacement: CGFloat = 50.0

    /// Minimum velocity (points/sec) during segments to filter out slow movement
    var minimumSegmentVelocity: CGFloat = 800.0

    /// Cooldown period after a shake is detected
    var cooldownDuration: TimeInterval = 1.0

    // MARK: - Internal State

    private var samples: [MouseSample] = []
    private let maxSamples = 128
    private var lastShakeTimestamp: TimeInterval = 0

    // MARK: - API

    /// Called on every mouse event. Returns true if a shake was just detected.
    mutating func addSample(_ sample: MouseSample) -> Bool {
        // Append and prune old samples
        samples.append(sample)
        let cutoff = sample.timestamp - (timeWindow + 0.25)
        if let firstValid = samples.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstValid > 0 { samples.removeFirst(firstValid) }
        } else {
            samples.removeAll()
            return false
        }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }

        // Cooldown check
        if sample.timestamp - lastShakeTimestamp < cooldownDuration {
            return false
        }

        // Need at least a few samples
        guard samples.count >= 4 else { return false }

        // Determine dominant axis from total displacement across the window
        let dominantAxis = computeDominantAxis()

        // Count reversals along the dominant axis
        let reversals = countReversals(along: dominantAxis)

        if reversals >= requiredReversals {
            lastShakeTimestamp = sample.timestamp
            return true
        }

        return false
    }

    /// Reset all state
    mutating func reset() {
        samples.removeAll()
        lastShakeTimestamp = 0
    }

    // MARK: - Private

    /// Compute a unit vector representing the dominant axis of motion.
    /// Uses the direction with the greatest absolute displacement sum.
    private func computeDominantAxis() -> CGVector {
        var totalDx: CGFloat = 0
        var totalDy: CGFloat = 0
        for i in 1..<samples.count {
            totalDx += abs(samples[i].location.x - samples[i - 1].location.x)
            totalDy += abs(samples[i].location.y - samples[i - 1].location.y)
        }
        // Normalize to unit vector along the dominant direction
        let magnitude = sqrt(totalDx * totalDx + totalDy * totalDy)
        guard magnitude > 0 else { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: totalDx / magnitude, dy: totalDy / magnitude)
    }

    /// Count direction reversals when movement is projected onto the given axis.
    private func countReversals(along axis: CGVector) -> Int {
        // Build segments: contiguous runs of movement in the same direction on the projected axis
        struct Segment {
            var startTimestamp: TimeInterval
            var endTimestamp: TimeInterval
            var projectedDisplacement: CGFloat // signed
        }

        var segments: [Segment] = []
        var currentSegment: Segment?

        for i in 1..<samples.count {
            let dx = samples[i].location.x - samples[i - 1].location.x
            let dy = samples[i].location.y - samples[i - 1].location.y
            // Project delta onto dominant axis
            let projectedDelta = dx * axis.dx + dy * axis.dy

            if projectedDelta == 0 { continue }

            if var seg = currentSegment {
                let sameDirection = (projectedDelta > 0) == (seg.projectedDisplacement > 0)
                if sameDirection {
                    seg.projectedDisplacement += projectedDelta
                    seg.endTimestamp = samples[i].timestamp
                    currentSegment = seg
                } else {
                    segments.append(seg)
                    currentSegment = Segment(
                        startTimestamp: samples[i - 1].timestamp,
                        endTimestamp: samples[i].timestamp,
                        projectedDisplacement: projectedDelta
                    )
                }
            } else {
                currentSegment = Segment(
                    startTimestamp: samples[i - 1].timestamp,
                    endTimestamp: samples[i].timestamp,
                    projectedDisplacement: projectedDelta
                )
            }
        }
        if let seg = currentSegment {
            segments.append(seg)
        }

        // Count reversals: direction changes between consecutive segments
        // that meet displacement and velocity thresholds
        var reversals = 0
        let now = samples.last?.timestamp ?? 0
        let windowStart = now - timeWindow

        for i in 1..<segments.count {
            let prev = segments[i - 1]
            let curr = segments[i]

            // Both segments must be within the time window
            guard curr.endTimestamp >= windowStart && prev.startTimestamp >= windowStart else { continue }

            // Check displacement threshold on the preceding segment
            let prevDisplacement = abs(prev.projectedDisplacement)
            guard prevDisplacement >= minimumSegmentDisplacement else { continue }

            // Check velocity threshold on the preceding segment
            let prevDuration = prev.endTimestamp - prev.startTimestamp
            guard prevDuration > 0 else { continue }
            let prevVelocity = prevDisplacement / CGFloat(prevDuration)
            guard prevVelocity >= minimumSegmentVelocity else { continue }

            // Direction must have actually reversed
            let reversed = (prev.projectedDisplacement > 0) != (curr.projectedDisplacement > 0)
            if reversed {
                reversals += 1
            }
        }

        return reversals
    }
}
