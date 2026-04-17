import Foundation

struct TrailPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // Visibility
    var isTrailVisible: Bool
    var isRippleEnabled: Bool
    var isCrosshairVisible: Bool
    var isShakeToggleEnabled: Bool

    // Trail Width
    var maxWidth: Double
    var glowWidthMultiplier: Double
    var trailAlgorithm: TrailAlgorithm

    // Movement
    var movementThreshold: Double
    var minimumVelocity: Double

    // Fade Duration
    var coreFadeTime: Double
    var glowFadeTime: Double

    // Core Trail Color (hex: #RRGGBB)
    var coreTrailHex: String

    // Glow Trail Color (hex: #RRGGBB)
    var glowTrailHex: String

    // Glow Opacity
    var glowOuterOpacity: Double
    var glowMiddleOpacity: Double

    // Crosshair Appearance
    var crosshairHex: String
    var crosshairOpacity: Double
    var crosshairLineWidth: Double

    // Ripple Effect
    var rippleRadius: Double
    var rippleSpeed: Double
    var rippleWavelength: Double
    var rippleDamping: Double
    var rippleAmplitude: Double
    var rippleDuration: Double
    var rippleSpecularIntensity: Double

    /// Compare only the setting values, ignoring id/name/dates.
    func settingsMatch(_ other: TrailPreset) -> Bool {
        isTrailVisible == other.isTrailVisible
            && isRippleEnabled == other.isRippleEnabled
            && isCrosshairVisible == other.isCrosshairVisible
            && isShakeToggleEnabled == other.isShakeToggleEnabled
            && maxWidth == other.maxWidth
            && glowWidthMultiplier == other.glowWidthMultiplier
            && trailAlgorithm == other.trailAlgorithm
            && movementThreshold == other.movementThreshold
            && minimumVelocity == other.minimumVelocity
            && coreFadeTime == other.coreFadeTime
            && glowFadeTime == other.glowFadeTime
            && coreTrailHex == other.coreTrailHex
            && glowTrailHex == other.glowTrailHex
            && glowOuterOpacity == other.glowOuterOpacity
            && glowMiddleOpacity == other.glowMiddleOpacity
            && crosshairHex == other.crosshairHex
            && crosshairOpacity == other.crosshairOpacity
            && crosshairLineWidth == other.crosshairLineWidth
            && rippleRadius == other.rippleRadius
            && rippleSpeed == other.rippleSpeed
            && rippleWavelength == other.rippleWavelength
            && rippleDamping == other.rippleDamping
            && rippleAmplitude == other.rippleAmplitude
            && rippleDuration == other.rippleDuration
            && rippleSpecularIntensity == other.rippleSpecularIntensity
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
        case isCrosshairVisible
        case isShakeToggleEnabled
        case maxWidth
        case glowWidthMultiplier
        case trailAlgorithm
        case movementThreshold
        case minimumVelocity
        case coreFadeTime
        case glowFadeTime
        case coreTrailHex
        case glowTrailHex
        case glowOuterOpacity
        case glowMiddleOpacity
        case crosshairHex
        case crosshairOpacity
        case crosshairLineWidth
        case rippleRadius
        case rippleSpeed
        case rippleWavelength
        case rippleDamping
        case rippleAmplitude
        case rippleDuration
        case rippleSpecularIntensity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isTrailVisible = try container.decode(Bool.self, forKey: .isTrailVisible)
        isRippleEnabled = try container.decode(Bool.self, forKey: .isRippleEnabled)
        isCrosshairVisible = try container.decodeIfPresent(Bool.self, forKey: .isCrosshairVisible) ?? false
        isShakeToggleEnabled = try container.decodeIfPresent(Bool.self, forKey: .isShakeToggleEnabled) ?? false
        maxWidth = try container.decode(Double.self, forKey: .maxWidth)
        glowWidthMultiplier = try container.decode(Double.self, forKey: .glowWidthMultiplier)
        trailAlgorithm = try container.decodeIfPresent(TrailAlgorithm.self, forKey: .trailAlgorithm) ?? .smooth
        movementThreshold = try container.decode(Double.self, forKey: .movementThreshold)
        minimumVelocity = try container.decode(Double.self, forKey: .minimumVelocity)
        coreFadeTime = try container.decode(Double.self, forKey: .coreFadeTime)
        glowFadeTime = try container.decode(Double.self, forKey: .glowFadeTime)
        coreTrailHex = try container.decode(String.self, forKey: .coreTrailHex)
        glowTrailHex = try container.decode(String.self, forKey: .glowTrailHex)
        glowOuterOpacity = try container.decode(Double.self, forKey: .glowOuterOpacity)
        glowMiddleOpacity = try container.decode(Double.self, forKey: .glowMiddleOpacity)
        crosshairHex = try container.decode(String.self, forKey: .crosshairHex)
        crosshairOpacity = try container.decodeIfPresent(Double.self, forKey: .crosshairOpacity) ?? 0.3
        crosshairLineWidth = try container.decodeIfPresent(Double.self, forKey: .crosshairLineWidth) ?? 1.0
        rippleRadius = try container.decodeIfPresent(Double.self, forKey: .rippleRadius) ?? 150.0
        rippleSpeed = try container.decodeIfPresent(Double.self, forKey: .rippleSpeed) ?? 120.0
        rippleWavelength = try container.decodeIfPresent(Double.self, forKey: .rippleWavelength) ?? 25.0
        rippleDamping = try container.decodeIfPresent(Double.self, forKey: .rippleDamping) ?? 2.0
        rippleAmplitude = try container.decodeIfPresent(Double.self, forKey: .rippleAmplitude) ?? 12.0
        rippleDuration = try container.decodeIfPresent(Double.self, forKey: .rippleDuration) ?? 1.2
        rippleSpecularIntensity = try container.decodeIfPresent(Double.self, forKey: .rippleSpecularIntensity) ?? 0.8
    }

    init(name: String, from settings: TrailSettings) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isTrailVisible = settings.isTrailVisible
        self.isRippleEnabled = settings.isRippleEnabled
        self.isCrosshairVisible = settings.isCrosshairVisible
        self.isShakeToggleEnabled = settings.isShakeToggleEnabled
        self.maxWidth = settings.maxWidth
        self.glowWidthMultiplier = settings.glowWidthMultiplier
        self.trailAlgorithm = settings.trailAlgorithm
        self.movementThreshold = settings.movementThreshold
        self.minimumVelocity = settings.minimumVelocity
        self.coreFadeTime = settings.coreFadeTime
        self.glowFadeTime = settings.glowFadeTime
        self.coreTrailHex = settings.coreTrailColorValue.hex
        self.glowTrailHex = settings.glowTrailColorValue.hex
        self.glowOuterOpacity = settings.glowOuterOpacity
        self.glowMiddleOpacity = settings.glowMiddleOpacity
        self.crosshairHex = settings.crosshairColorValue.hex
        self.crosshairOpacity = settings.crosshairOpacity
        self.crosshairLineWidth = settings.crosshairLineWidth
        self.rippleRadius = settings.rippleRadius
        self.rippleSpeed = settings.rippleSpeed
        self.rippleWavelength = settings.rippleWavelength
        self.rippleDamping = settings.rippleDamping
        self.rippleAmplitude = settings.rippleAmplitude
        self.rippleDuration = settings.rippleDuration
        self.rippleSpecularIntensity = settings.rippleSpecularIntensity
    }
}
