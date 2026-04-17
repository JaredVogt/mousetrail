import Foundation

/// Rich event returned when a shake gesture is detected, including the axis angle
/// so callers can route different shake directions to different actions.
struct ShakeEvent {
    /// Dominant axis angle in radians [0, π). 0 = horizontal, π/2 = vertical.
    /// Normalized to [0, π) because shakes are bidirectional.
    let axisAngle: CGFloat

    /// Number of direction reversals detected
    let reversals: Int

    /// Mean velocity (points/sec) across qualifying segments
    let averageVelocity: CGFloat

    /// Angular spread (radians) of segments relative to the dominant axis
    let angularSpread: CGFloat

    let timestamp: TimeInterval
}

/// Detects rapid back-and-forth mouse shaking along any axis.
/// Works by counting direction reversals projected onto the dominant axis of motion.
/// Returns a ShakeEvent with axis information so directional shakes can be distinguished.
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

    /// Maximum angular deviation (radians) a segment can have from the dominant axis.
    /// Segments deviating more than this are rejected, enforcing that the shake
    /// stays on a consistent line. Default π/4 (45°).
    var maximumAngularDeviation: CGFloat = .pi / 4

    // MARK: - Internal State

    private var samples: [MouseSample] = []
    private let maxSamples = 128
    private var lastShakeTimestamp: TimeInterval = 0

    // MARK: - API

    /// Called on every mouse event. Returns a ShakeEvent if a shake was just detected, nil otherwise.
    mutating func addSample(_ sample: MouseSample) -> ShakeEvent? {
        // Guard against clock jumps (sleep/wake, NTP correction) — reset on backward time.
        if let last = samples.last, sample.timestamp < last.timestamp {
            reset()
            samples.append(sample)
            return nil
        }

        // Append and prune old samples
        samples.append(sample)
        let cutoff = sample.timestamp - (timeWindow + 0.25)
        if let firstValid = samples.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstValid > 0 { samples.removeFirst(firstValid) }
        } else {
            samples.removeAll()
            return nil
        }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }

        // Cooldown check
        if sample.timestamp - lastShakeTimestamp < cooldownDuration {
            return nil
        }

        // Need at least a few samples
        guard samples.count >= 4 else { return nil }

        // Determine dominant axis from total displacement across the window
        let dominantAxis = ShakeAxisMath.dominantAxis(from: samples)
        guard dominantAxis.dx != 0 || dominantAxis.dy != 0 else { return nil }
        let axisAngle = atan2(dominantAxis.dy, dominantAxis.dx)

        // Count reversals along the dominant axis, enforcing angular coherence
        let result = countReversals(along: dominantAxis, axisAngle: axisAngle)

        if result.reversals >= requiredReversals {
            lastShakeTimestamp = sample.timestamp
            // Normalize axis angle to [0, π) since shakes are bidirectional
            var normalizedAngle = axisAngle
            while normalizedAngle < 0 { normalizedAngle += .pi }
            while normalizedAngle >= .pi { normalizedAngle -= .pi }

            return ShakeEvent(
                axisAngle: normalizedAngle,
                reversals: result.reversals,
                averageVelocity: result.averageVelocity,
                angularSpread: result.angularSpread,
                timestamp: sample.timestamp
            )
        }

        return nil
    }

    /// Reset all state
    mutating func reset() {
        samples.removeAll()
        lastShakeTimestamp = 0
    }

    // MARK: - Private

    private struct ReversalResult {
        let reversals: Int
        let averageVelocity: CGFloat
        let angularSpread: CGFloat
    }

    /// Count direction reversals when movement is projected onto the given axis,
    /// rejecting segments that deviate too far from the axis angle.
    private func countReversals(along axis: CGVector, axisAngle: CGFloat) -> ReversalResult {
        let segments = ShakeAxisMath.buildSegments(from: samples, axis: axis)

        // Count reversals: direction changes between consecutive segments
        // that meet displacement, velocity, and angular coherence thresholds
        guard segments.count > 1 else { return ReversalResult(reversals: 0, averageVelocity: 0, angularSpread: 0) }
        var reversals = 0
        var velocitySum: CGFloat = 0
        var velocityCount = 0
        var angularDeviationSum: CGFloat = 0
        var angularDeviationCount = 0
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

            // Angular coherence check: segment direction must be within tolerance of dominant axis.
            // Compare modulo π since segments alternate direction.
            let segAngle = atan2(prev.rawDy, prev.rawDx)
            var angleDiff = segAngle - axisAngle
            // Normalize to [-π, π]
            while angleDiff > .pi { angleDiff -= 2 * .pi }
            while angleDiff < -.pi { angleDiff += 2 * .pi }
            // Modulo π: a segment going "backwards" along the axis is fine
            if angleDiff > .pi / 2 { angleDiff -= .pi }
            if angleDiff < -.pi / 2 { angleDiff += .pi }
            let absDeviation = abs(angleDiff)
            guard absDeviation <= maximumAngularDeviation else { continue }
            angularDeviationSum += absDeviation
            angularDeviationCount += 1

            // Direction must have actually reversed
            let reversed = (prev.projectedDisplacement > 0) != (curr.projectedDisplacement > 0)
            if reversed {
                reversals += 1
                velocitySum += prevVelocity
                velocityCount += 1
            }
        }

        let avgVelocity = velocityCount > 0 ? velocitySum / CGFloat(velocityCount) : 0
        let avgSpread = angularDeviationCount > 0 ? angularDeviationSum / CGFloat(angularDeviationCount) : 0

        return ReversalResult(reversals: reversals, averageVelocity: avgVelocity, angularSpread: avgSpread)
    }
}
