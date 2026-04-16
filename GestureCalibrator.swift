import Foundation

/// Result of analyzing a recorded shake gesture for calibration.
struct ShakeCalibrationResult {
    /// Detected dominant axis angle in degrees [0, 180)
    let axisAngleDegrees: CGFloat
    /// Angular spread of segments in degrees
    let angularSpreadDegrees: CGFloat
    /// Suggested tolerance (spread + safety margin)
    let suggestedToleranceDegrees: CGFloat
    /// Number of reversals detected
    let reversals: Int
    /// Min/max/mean segment displacement
    let minDisplacement: CGFloat
    let maxDisplacement: CGFloat
    let meanDisplacement: CGFloat
    /// Min/max/mean segment velocity
    let minVelocity: CGFloat
    let maxVelocity: CGFloat
    let meanVelocity: CGFloat
    /// Total duration of the recorded gesture
    let duration: TimeInterval
}

/// Analyzes recorded mouse samples to derive gesture detection parameters.
struct GestureCalibrator {
    /// Minimum samples required for a valid calibration recording
    static let minimumSamples = 10

    /// Pause duration (seconds) that signals end of gesture recording
    static let pauseThreshold: TimeInterval = 0.75

    /// Analyze a recorded sequence of mouse samples as a shake gesture.
    /// Uses the same segment-building logic as ShakeDetector.
    static func analyzeShake(samples: [MouseSample]) -> ShakeCalibrationResult? {
        guard samples.count >= minimumSamples else { return nil }

        // Compute dominant axis from total displacement
        var totalDx: CGFloat = 0
        var totalDy: CGFloat = 0
        for i in 1..<samples.count {
            totalDx += abs(samples[i].location.x - samples[i - 1].location.x)
            totalDy += abs(samples[i].location.y - samples[i - 1].location.y)
        }
        let magnitude = sqrt(totalDx * totalDx + totalDy * totalDy)
        guard magnitude > 0 else { return nil }
        let axisDx = totalDx / magnitude
        let axisDy = totalDy / magnitude
        let axisAngle = atan2(axisDy, axisDx)

        // Build segments (same logic as ShakeDetector)
        struct Segment {
            var startTimestamp: TimeInterval
            var endTimestamp: TimeInterval
            var projectedDisplacement: CGFloat
            var rawDx: CGFloat
            var rawDy: CGFloat
        }

        var segments: [Segment] = []
        var currentSegment: Segment?

        for i in 1..<samples.count {
            let dx = samples[i].location.x - samples[i - 1].location.x
            let dy = samples[i].location.y - samples[i - 1].location.y
            let projectedDelta = dx * axisDx + dy * axisDy
            if projectedDelta == 0 { continue }

            if var seg = currentSegment {
                let sameDirection = (projectedDelta > 0) == (seg.projectedDisplacement > 0)
                if sameDirection {
                    seg.projectedDisplacement += projectedDelta
                    seg.rawDx += dx
                    seg.rawDy += dy
                    seg.endTimestamp = samples[i].timestamp
                    currentSegment = seg
                } else {
                    segments.append(seg)
                    currentSegment = Segment(
                        startTimestamp: samples[i - 1].timestamp,
                        endTimestamp: samples[i].timestamp,
                        projectedDisplacement: projectedDelta,
                        rawDx: dx,
                        rawDy: dy
                    )
                }
            } else {
                currentSegment = Segment(
                    startTimestamp: samples[i - 1].timestamp,
                    endTimestamp: samples[i].timestamp,
                    projectedDisplacement: projectedDelta,
                    rawDx: dx,
                    rawDy: dy
                )
            }
        }
        if let seg = currentSegment { segments.append(seg) }

        // Need at least 2 segments to have a reversal
        guard segments.count >= 2 else { return nil }

        // Analyze segments
        var displacements: [CGFloat] = []
        var velocities: [CGFloat] = []
        var angularDeviations: [CGFloat] = []
        var reversals = 0

        for i in 0..<segments.count {
            let seg = segments[i]
            let displacement = abs(seg.projectedDisplacement)
            let duration = seg.endTimestamp - seg.startTimestamp
            if duration > 0 {
                displacements.append(displacement)
                velocities.append(displacement / CGFloat(duration))
            }

            // Compute angular deviation from dominant axis
            let segAngle = atan2(seg.rawDy, seg.rawDx)
            var angleDiff = segAngle - axisAngle
            while angleDiff > .pi { angleDiff -= 2 * .pi }
            while angleDiff < -.pi { angleDiff += 2 * .pi }
            // Modulo pi for bidirectional
            if angleDiff > .pi / 2 { angleDiff -= .pi }
            if angleDiff < -.pi / 2 { angleDiff += .pi }
            angularDeviations.append(abs(angleDiff))

            // Count reversals
            if i > 0 {
                let prev = segments[i - 1]
                let reversed = (prev.projectedDisplacement > 0) != (seg.projectedDisplacement > 0)
                if reversed { reversals += 1 }
            }
        }

        guard !displacements.isEmpty, !velocities.isEmpty else { return nil }

        let minDisp = displacements.min() ?? 0
        let maxDisp = displacements.max() ?? 0
        let meanDisp = displacements.reduce(0, +) / CGFloat(displacements.count)

        let minVel = velocities.min() ?? 0
        let maxVel = velocities.max() ?? 0
        let meanVel = velocities.reduce(0, +) / CGFloat(velocities.count)

        let maxSpread = angularDeviations.max() ?? 0
        let spreadDegrees = maxSpread * 180 / .pi

        // Normalize axis angle to [0, pi)
        var normalizedAngle = axisAngle
        while normalizedAngle < 0 { normalizedAngle += .pi }
        while normalizedAngle >= .pi { normalizedAngle -= .pi }
        let angleDegrees = normalizedAngle * 180 / .pi

        // Suggested tolerance: observed spread + 50% safety margin, clamped to [10, 45]
        let suggestedTolerance = max(10, min(45, spreadDegrees * 1.5 + 5))

        let duration = (samples.last?.timestamp ?? 0) - (samples.first?.timestamp ?? 0)

        return ShakeCalibrationResult(
            axisAngleDegrees: angleDegrees,
            angularSpreadDegrees: spreadDegrees,
            suggestedToleranceDegrees: suggestedTolerance,
            reversals: reversals,
            minDisplacement: minDisp,
            maxDisplacement: maxDisp,
            meanDisplacement: meanDisp,
            minVelocity: minVel,
            maxVelocity: maxVel,
            meanVelocity: meanVel,
            duration: duration
        )
    }
}

// MARK: - Calibration Recording State

/// Manages the state of a gesture calibration recording session.
/// Runs on AppCore — collects samples during recording and detects pause to auto-stop.
class CalibrationSession {
    enum State {
        case idle
        case recording
        case analyzing
        case complete(ShakeCalibrationResult)
        case failed(String)
    }

    private(set) var state: State = .idle
    private var recordedSamples: [MouseSample] = []
    private var lastSampleTimestamp: TimeInterval = 0
    var onStateChanged: ((State) -> Void)?

    func startRecording() {
        recordedSamples.removeAll()
        lastSampleTimestamp = 0
        state = .recording
        onStateChanged?(state)
    }

    /// Feed mouse samples during recording. Returns true if recording is still active.
    func addSample(_ sample: MouseSample) -> Bool {
        guard case .recording = state else { return false }

        // Check for pause (auto-stop)
        if !recordedSamples.isEmpty {
            let gap = sample.timestamp - lastSampleTimestamp
            if gap >= GestureCalibrator.pauseThreshold && recordedSamples.count >= GestureCalibrator.minimumSamples {
                // Pause detected — analyze
                finishRecording()
                return false
            }
        }

        recordedSamples.append(sample)
        lastSampleTimestamp = sample.timestamp
        return true
    }

    /// Manually stop recording and analyze.
    func stopRecording() {
        guard case .recording = state else { return }
        finishRecording()
    }

    func reset() {
        state = .idle
        recordedSamples.removeAll()
        lastSampleTimestamp = 0
        onStateChanged?(state)
    }

    private func finishRecording() {
        state = .analyzing
        onStateChanged?(state)

        if let result = GestureCalibrator.analyzeShake(samples: recordedSamples) {
            state = .complete(result)
        } else {
            state = .failed("Could not detect a shake gesture. Try a more pronounced back-and-forth motion.")
        }
        onStateChanged?(state)
    }

    var sampleCount: Int { recordedSamples.count }
}
