/**
 * MouseTrail - shared types and logging used across the app.
 */

import Cocoa

// Build timestamp - update this when making changes
let BUILD_TIMESTAMP = "2026-04-17 00:23:56"

@inline(__always)
func currentMonotonicTime() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}

/**
 * TrailPoint - Represents a single point in the mouse trail
 */
struct TrailPoint {
    let position: NSPoint
    let timestamp: TimeInterval
    let velocity: CGFloat // Speed in pixels per second
}

struct MouseSample {
    let location: NSPoint
    let timestamp: TimeInterval
}

struct SpringCursorState {
    var position: NSPoint
    var velocity: CGVector
    var timestamp: TimeInterval
}

struct PerformanceExperimentConfig {
    let reduceSyntheticSampleRate: Bool
    let enableSmoothInputCoalescing: Bool
    let useReducedLayerStack: Bool
    let onlyUpdateDirtyScreens: Bool
    let useLinearSmoothPlaybackLookup: Bool
    let useStrongerPointDecimation: Bool
    let useRelaxedPathRebuild: Bool
    let capTrailRenderingTo60FPS: Bool

    init(settings: TrailSettings) {
        reduceSyntheticSampleRate = settings.reduceSyntheticSampleRate
        enableSmoothInputCoalescing = settings.enableSmoothInputCoalescing
        useReducedLayerStack = settings.useReducedLayerStack
        onlyUpdateDirtyScreens = settings.onlyUpdateDirtyScreens
        useLinearSmoothPlaybackLookup = settings.useLinearSmoothPlaybackLookup
        useStrongerPointDecimation = settings.useStrongerPointDecimation
        useRelaxedPathRebuild = settings.useRelaxedPathRebuild
        capTrailRenderingTo60FPS = settings.capTrailRenderingTo60FPS
    }

    func mouseCoalescingEnabled(for algorithm: TrailAlgorithm) -> Bool {
        switch algorithm {
        case .spring:
            return true
        case .smooth:
            return enableSmoothInputCoalescing
        }
    }

    var syntheticSampleInterval: TimeInterval {
        reduceSyntheticSampleRate ? (1.0 / 120.0) : (1.0 / 240.0)
    }

    var trailMinimumPointDistance: CGFloat {
        useStrongerPointDecimation ? 1.5 : 0.5
    }

    var trailMaximumRenderSegmentLength: CGFloat {
        useRelaxedPathRebuild ? 10.0 : 6.0
    }

    var trailRenderSmoothingPasses: Int {
        useRelaxedPathRebuild ? 1 : 2
    }

    var trailMaxPoints: Int {
        useRelaxedPathRebuild ? 120 : 180
    }

    var trailRenderMinimumInterval: TimeInterval {
        capTrailRenderingTo60FPS ? (1.0 / 60.0) : 0
    }
}

// MARK: - Log Levels

enum LogLevel: Int, Comparable, CaseIterable {
    case off = 0
    case info = 1
    case debug = 2

    var label: String {
        switch self {
        case .off: return "Off"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }

    var prefix: String {
        switch self {
        case .off: return ""
        case .info: return "[info]"
        case .debug: return "[debug]"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Current log level — controlled via settings
var currentLogLevel: LogLevel = .info

/// Cached date formatter — avoids per-log allocation.
private let logTimestampFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "HH:mm:ss"
    return df
}()

/// Log at info level — high-level state changes, gesture detections, initialization.
/// @autoclosure lets the caller's string interpolation be skipped entirely when gated out.
func logInfo(_ message: @autoclosure () -> String) {
    guard LogLevel.info <= currentLogLevel else { return }
    writeLog(message(), level: .info)
}

/// Log at debug level — verbose coordinate dumps, rect calculations, capture details.
func logDebug(_ message: @autoclosure () -> String) {
    guard LogLevel.debug <= currentLogLevel else { return }
    writeLog(message(), level: .debug)
}

/// Legacy function — routes to logDebug for backward compatibility
func debugLog(_ message: @autoclosure () -> String) {
    guard LogLevel.debug <= currentLogLevel else { return }
    writeLog(message(), level: .debug)
}

private func writeLog(_ message: String, level: LogLevel) {
    let line = "[\(logTimestampFormatter.string(from: Date()))] \(level.prefix) \(message)"
    print(line)
    let fileLine = line + "\n"
    let logPath = LogFileViewer.logPath
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(fileLine.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: fileLine.data(using: .utf8))
    }
}
