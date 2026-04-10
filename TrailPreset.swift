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

    /// Compare only the 16 setting values, ignoring id/name/dates
    func settingsMatch(_ other: TrailPreset) -> Bool {
        isTrailVisible == other.isTrailVisible
            && isRippleEnabled == other.isRippleEnabled
            && maxWidth == other.maxWidth
            && blueWidthMultiplier == other.blueWidthMultiplier
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
    init(name: String, from settings: TrailSettings) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isTrailVisible = settings.isTrailVisible
        self.isRippleEnabled = settings.isRippleEnabled
        self.maxWidth = settings.maxWidth
        self.blueWidthMultiplier = settings.blueWidthMultiplier
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
