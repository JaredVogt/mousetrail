import Foundation

/// Shared interface for detectors that consume mouse samples and produce
/// gesture events. Conformers keep their own buffered state; the router fans
/// a single `feed` call out to whatever detectors are wired up.
protocol GestureDetector {
    associatedtype Event

    /// Consume one mouse sample. Returns a non-nil event on the sample that
    /// completes a gesture; returns nil otherwise.
    mutating func feed(_ sample: MouseSample) -> Event?

    /// Drop all buffered state.
    mutating func reset()
}
