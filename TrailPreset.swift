import Foundation

struct TrailPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // Visibility
    var isTrailVisible: Bool
    var isRippleEnabled: Bool

    // Trail Width
    var maxWidth: Double
    var blueWidthMultiplier: Double
    var trailAlgorithm: TrailAlgorithm

    // Movement
    var movementThreshold: Double
    var minimumVelocity: Double

    // Fade Duration
    var redFadeTime: Double
    var blueFadeTime: Double

    // Red Trail Color
    var redTrailR: Double
    var redTrailG: Double
    var redTrailB: Double

    // Blue Trail Color
    var blueTrailR: Double
    var blueTrailG: Double
    var blueTrailB: Double

    // Blue Glow Opacity
    var blueOuterOpacity: Double
    var blueMiddleOpacity: Double

    /// Compare only the setting values, ignoring id/name/dates.
    func settingsMatch(_ other: TrailPreset) -> Bool {
        isTrailVisible == other.isTrailVisible
            && isRippleEnabled == other.isRippleEnabled
            && maxWidth == other.maxWidth
            && blueWidthMultiplier == other.blueWidthMultiplier
            && trailAlgorithm == other.trailAlgorithm
            && movementThreshold == other.movementThreshold
            && minimumVelocity == other.minimumVelocity
            && redFadeTime == other.redFadeTime
            && blueFadeTime == other.blueFadeTime
            && redTrailR == other.redTrailR
            && redTrailG == other.redTrailG
            && redTrailB == other.redTrailB
            && blueTrailR == other.blueTrailR
            && blueTrailG == other.blueTrailG
            && blueTrailB == other.blueTrailB
            && blueOuterOpacity == other.blueOuterOpacity
            && blueMiddleOpacity == other.blueMiddleOpacity
    }
}

extension TrailPreset {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case updatedAt
        case isTrailVisible
        case isRippleEnabled
        case maxWidth
        case blueWidthMultiplier
        case trailAlgorithm
        case movementThreshold
        case minimumVelocity
        case redFadeTime
        case blueFadeTime
        case redTrailR
        case redTrailG
        case redTrailB
        case blueTrailR
        case blueTrailG
        case blueTrailB
        case blueOuterOpacity
        case blueMiddleOpacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isTrailVisible = try container.decode(Bool.self, forKey: .isTrailVisible)
        isRippleEnabled = try container.decode(Bool.self, forKey: .isRippleEnabled)
        maxWidth = try container.decode(Double.self, forKey: .maxWidth)
        blueWidthMultiplier = try container.decode(Double.self, forKey: .blueWidthMultiplier)
        trailAlgorithm = try container.decodeIfPresent(TrailAlgorithm.self, forKey: .trailAlgorithm) ?? .smooth
        movementThreshold = try container.decode(Double.self, forKey: .movementThreshold)
        minimumVelocity = try container.decode(Double.self, forKey: .minimumVelocity)
        redFadeTime = try container.decode(Double.self, forKey: .redFadeTime)
        blueFadeTime = try container.decode(Double.self, forKey: .blueFadeTime)
        redTrailR = try container.decode(Double.self, forKey: .redTrailR)
        redTrailG = try container.decode(Double.self, forKey: .redTrailG)
        redTrailB = try container.decode(Double.self, forKey: .redTrailB)
        blueTrailR = try container.decode(Double.self, forKey: .blueTrailR)
        blueTrailG = try container.decode(Double.self, forKey: .blueTrailG)
        blueTrailB = try container.decode(Double.self, forKey: .blueTrailB)
        blueOuterOpacity = try container.decode(Double.self, forKey: .blueOuterOpacity)
        blueMiddleOpacity = try container.decode(Double.self, forKey: .blueMiddleOpacity)
    }

    init(name: String, from settings: TrailSettings) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isTrailVisible = settings.isTrailVisible
        self.isRippleEnabled = settings.isRippleEnabled
        self.maxWidth = settings.maxWidth
        self.blueWidthMultiplier = settings.blueWidthMultiplier
        self.trailAlgorithm = settings.trailAlgorithm
        self.movementThreshold = settings.movementThreshold
        self.minimumVelocity = settings.minimumVelocity
        self.redFadeTime = settings.redFadeTime
        self.blueFadeTime = settings.blueFadeTime
        self.redTrailR = settings.redTrailR
        self.redTrailG = settings.redTrailG
        self.redTrailB = settings.redTrailB
        self.blueTrailR = settings.blueTrailR
        self.blueTrailG = settings.blueTrailG
        self.blueTrailB = settings.blueTrailB
        self.blueOuterOpacity = settings.blueOuterOpacity
        self.blueMiddleOpacity = settings.blueMiddleOpacity
    }
}
