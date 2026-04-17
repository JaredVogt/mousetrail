import Foundation

/// A contiguous run of motion in the same direction when projected onto a given axis.
/// Shared by `ShakeDetector` (live detection) and `GestureCalibrator` (post-hoc analysis).
struct ShakeSegment {
    var startTimestamp: TimeInterval
    var endTimestamp: TimeInterval
    /// Signed projection of accumulated motion onto the axis.
    var projectedDisplacement: CGFloat
    /// Raw total deltas for angular analysis (segment direction).
    var rawDx: CGFloat
    var rawDy: CGFloat
}

enum ShakeAxisMath {
    /// Compute the dominant axis of motion from a sample sequence as a unit vector.
    /// Returns the zero vector if no motion is present.
    static func dominantAxis(from samples: [MouseSample]) -> CGVector {
        var totalDx: CGFloat = 0
        var totalDy: CGFloat = 0
        for i in 1..<samples.count {
            totalDx += abs(samples[i].location.x - samples[i - 1].location.x)
            totalDy += abs(samples[i].location.y - samples[i - 1].location.y)
        }
        let magnitude = sqrt(totalDx * totalDx + totalDy * totalDy)
        guard magnitude > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: totalDx / magnitude, dy: totalDy / magnitude)
    }

    /// Split a sample sequence into segments of continuous motion along `axis`.
    /// Identical logic was previously duplicated in `ShakeDetector` and `GestureCalibrator`.
    static func buildSegments(from samples: [MouseSample], axis: CGVector) -> [ShakeSegment] {
        var segments: [ShakeSegment] = []
        var current: ShakeSegment?

        for i in 1..<samples.count {
            let dx = samples[i].location.x - samples[i - 1].location.x
            let dy = samples[i].location.y - samples[i - 1].location.y
            let projectedDelta = dx * axis.dx + dy * axis.dy
            if projectedDelta == 0 { continue }

            if var seg = current,
               (projectedDelta > 0) == (seg.projectedDisplacement > 0) {
                seg.projectedDisplacement += projectedDelta
                seg.rawDx += dx
                seg.rawDy += dy
                seg.endTimestamp = samples[i].timestamp
                current = seg
            } else {
                if let seg = current { segments.append(seg) }
                current = ShakeSegment(
                    startTimestamp: samples[i - 1].timestamp,
                    endTimestamp: samples[i].timestamp,
                    projectedDisplacement: projectedDelta,
                    rawDx: dx,
                    rawDy: dy
                )
            }
        }
        if let seg = current { segments.append(seg) }
        return segments
    }
}
