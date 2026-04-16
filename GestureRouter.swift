import Foundation
import AppKit

// MARK: - Gesture Actions

/// Modifier keys for gesture-triggered key simulations, Codable-friendly.
enum GestureModifierKey: String, Codable, CaseIterable {
    case shift
    case control
    case option
    case command

    var cgEventFlag: CGEventFlags {
        switch self {
        case .shift:   return .maskShift
        case .control: return .maskControl
        case .option:  return .maskAlternate
        case .command: return .maskCommand
        }
    }

    var displaySymbol: String {
        switch self {
        case .shift:   return "⇧"
        case .control: return "⌃"
        case .option:  return "⌥"
        case .command: return "⌘"
        }
    }
}

/// An action that can be triggered by a gesture.
enum GestureAction: Codable, Equatable {
    case none
    case toggleVisuals
    case simulateKeyPress(keyCode: UInt16, modifiers: [GestureModifierKey])
    case runShellCommand(command: String)

    var displayName: String {
        switch self {
        case .none: return "None"
        case .toggleVisuals: return "Toggle Visuals"
        case .simulateKeyPress(let keyCode, let modifiers):
            let modStr = modifiers.map { $0.displaySymbol }.joined()
            let keyStr = GestureAction.keyCodeDisplayName(keyCode)
            return "\(modStr)\(keyStr)"
        case .runShellCommand(let command):
            let truncated = command.count > 20 ? String(command.prefix(20)) + "..." : command
            return "Run: \(truncated)"
        }
    }

    private static let keyCodeNames: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1",
        0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L",
        0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",",
        0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
        0x24: "\u{21A9}", 0x30: "\u{21E5}", 0x31: "\u{2423}",
        0x33: "\u{232B}", 0x35: "\u{238B}",
    ]

    static func keyCodeDisplayName(_ code: UInt16) -> String {
        keyCodeNames[code] ?? String(format: "0x%02X", code)
    }
}

// MARK: - Shake Zones

/// Defines an angular range for a named directional shake gesture.
/// Angles are in degrees [0, 180) because shakes are bidirectional.
struct ShakeZone: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Center angle in degrees [0, 180). 0 = horizontal, 90 = vertical.
    var centerAngleDegrees: CGFloat
    /// Half-width tolerance in degrees. Zone matches if within ±tolerance of center.
    var toleranceDegrees: CGFloat
    var action: GestureAction
    var isEnabled: Bool

    /// Check if a given axis angle (in radians, [0, π)) falls within this zone.
    func matches(axisAngle: CGFloat) -> Bool {
        guard isEnabled else { return false }
        let angleDeg = axisAngle * 180 / .pi
        // Compute angular distance on the [0, 180) circle
        var diff = abs(angleDeg - centerAngleDegrees)
        if diff > 90 { diff = 180 - diff }
        return diff <= toleranceDegrees
    }

    static func defaultZones() -> [ShakeZone] {
        [
            ShakeZone(
                id: UUID(),
                name: "Horizontal Shake",
                centerAngleDegrees: 0,
                toleranceDegrees: 20,
                action: .toggleVisuals,
                isEnabled: true
            ),
            ShakeZone(
                id: UUID(),
                name: "Vertical Shake",
                centerAngleDegrees: 90,
                toleranceDegrees: 20,
                action: .none,
                isEnabled: false
            ),
            ShakeZone(
                id: UUID(),
                name: "Diagonal Up Shake",
                centerAngleDegrees: 45,
                toleranceDegrees: 15,
                action: .none,
                isEnabled: false
            ),
            ShakeZone(
                id: UUID(),
                name: "Diagonal Down Shake",
                centerAngleDegrees: 135,
                toleranceDegrees: 15,
                action: .none,
                isEnabled: false
            ),
        ]
    }
}

// MARK: - Circle Gesture Config

/// Configuration for circle gesture actions, optionally distinguished by direction.
struct CircleGestureConfig: Codable, Equatable {
    var isEnabled: Bool = true
    /// Action for clockwise circles (or any direction if directionMatters is false)
    var clockwiseAction: GestureAction = .simulateKeyPress(keyCode: 0x15, modifiers: [.shift, .control, .command])
    /// Action for counter-clockwise circles
    var counterClockwiseAction: GestureAction = .none
    /// If false, clockwiseAction is used regardless of direction
    var directionMatters: Bool = false

    func action(for direction: CircleDirection) -> GestureAction {
        guard isEnabled else { return .none }
        if !directionMatters { return clockwiseAction }
        switch direction {
        case .clockwise: return clockwiseAction
        case .counterClockwise: return counterClockwiseAction
        }
    }

    /// Action for hyper+circle (preserved from existing behavior)
    var hyperClockwiseAction: GestureAction = .simulateKeyPress(keyCode: 0x13, modifiers: [.shift, .control, .command])
    var hyperCounterClockwiseAction: GestureAction = .none
    var hyperDirectionMatters: Bool = false

    func hyperAction(for direction: CircleDirection) -> GestureAction {
        guard isEnabled else { return .none }
        if !hyperDirectionMatters { return hyperClockwiseAction }
        switch direction {
        case .clockwise: return hyperClockwiseAction
        case .counterClockwise: return hyperCounterClockwiseAction
        }
    }
}

// MARK: - Gesture Router

/// Routes gesture events to actions based on configured zones and settings.
struct GestureRouter {
    var shakeZones: [ShakeZone]
    var circleConfig: CircleGestureConfig

    /// Find the matching shake zone for a shake event. Returns the best match
    /// (smallest tolerance if multiple zones match).
    func matchingZone(for event: ShakeEvent) -> ShakeZone? {
        var bestMatch: ShakeZone? = nil
        var bestTolerance: CGFloat = .greatestFiniteMagnitude
        for zone in shakeZones {
            if zone.matches(axisAngle: event.axisAngle) && zone.toleranceDegrees < bestTolerance {
                bestMatch = zone
                bestTolerance = zone.toleranceDegrees
            }
        }
        return bestMatch
    }

    /// Get the action for a circle event.
    func action(for event: CircleEvent, isHyperPressed: Bool) -> GestureAction {
        if isHyperPressed {
            return circleConfig.hyperAction(for: event.direction)
        }
        return circleConfig.action(for: event.direction)
    }

    /// Execute a gesture action. Returns true if an action was performed.
    @discardableResult
    func execute(_ action: GestureAction, simulateKeyPress: (CGKeyCode, CGEventFlags) -> Void) -> Bool {
        switch action {
        case .none:
            return false
        case .toggleVisuals:
            // Caller handles this since it needs AppCore state
            return true
        case .simulateKeyPress(let keyCode, let modifiers):
            var flags = CGEventFlags()
            for mod in modifiers {
                flags.insert(mod.cgEventFlag)
            }
            simulateKeyPress(keyCode, flags)
            return true
        case .runShellCommand(let command):
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["bash", "-c", command]
                try? process.run()
            }
            return true
        }
    }
}

// MARK: - Persistence Helpers

/// UserDefaults key for gesture configuration
private let gestureConfigKey = "gesture.config"

struct GestureConfigData: Codable {
    var shakeZones: [ShakeZone]
    var circleConfig: CircleGestureConfig
}

func saveGestureConfig(zones: [ShakeZone], circleConfig: CircleGestureConfig) {
    let data = GestureConfigData(shakeZones: zones, circleConfig: circleConfig)
    if let encoded = try? JSONEncoder().encode(data) {
        UserDefaults.standard.set(encoded, forKey: gestureConfigKey)
    }
}

func loadGestureConfig() -> GestureConfigData {
    guard let data = UserDefaults.standard.data(forKey: gestureConfigKey),
          let config = try? JSONDecoder().decode(GestureConfigData.self, from: data) else {
        return GestureConfigData(
            shakeZones: ShakeZone.defaultZones(),
            circleConfig: CircleGestureConfig()
        )
    }
    return config
}
