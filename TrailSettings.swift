import Foundation
import AppKit
import SwiftUI

@Observable
class TrailSettings {
    /// Callback when trail appearance settings change
    var onChanged: (() -> Void)?
    /// Callback when visibility toggles change
    var onVisibilityChanged: (() -> Void)?

    // MARK: - Visibility

    var isTrailVisible = true { didSet { save(); onVisibilityChanged?() } }
    var isInfoPanelVisible = false { didSet { save(); onVisibilityChanged?() } }
    var isRippleEnabled = false { didSet { save(); onVisibilityChanged?() } }

    // MARK: - Trail Width

    var maxWidth = 8.0 { didSet { save(); onChanged?() } }
    var blueWidthMultiplier = 3.5 { didSet { save(); onChanged?() } }

    // MARK: - Movement

    var movementThreshold = 30.0 { didSet { save(); onChanged?() } }
    var minimumVelocity = 0.0 { didSet { save(); onChanged?() } }

    // MARK: - Fade Duration

    var redFadeTime = 0.6 { didSet { save(); onChanged?() } }
    var blueFadeTime = 0.35 { didSet { save(); onChanged?() } }

    // MARK: - Red Trail Color (RGB components)

    var redTrailR = 1.0 { didSet { save(); onChanged?() } }
    var redTrailG = 0.15 { didSet { save(); onChanged?() } }
    var redTrailB = 0.1 { didSet { save(); onChanged?() } }

    // MARK: - Blue Trail Color (RGB components)

    var blueTrailR = 0.1 { didSet { save(); onChanged?() } }
    var blueTrailG = 0.5 { didSet { save(); onChanged?() } }
    var blueTrailB = 1.0 { didSet { save(); onChanged?() } }

    // MARK: - Blue Trail Opacity

    var blueOuterOpacity = 0.02 { didSet { save(); onChanged?() } }
    var blueMiddleOpacity = 0.08 { didSet { save(); onChanged?() } }

    // MARK: - Computed Colors

    var redTrailColor: Color {
        get { Color(red: redTrailR, green: redTrailG, blue: redTrailB) }
        set {
            guard let components = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            redTrailR = components.redComponent
            redTrailG = components.greenComponent
            redTrailB = components.blueComponent
        }
    }

    var blueTrailColor: Color {
        get { Color(red: blueTrailR, green: blueTrailG, blue: blueTrailB) }
        set {
            guard let components = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            blueTrailR = components.redComponent
            blueTrailG = components.greenComponent
            blueTrailB = components.blueComponent
        }
    }

    var redTrailNSColor: NSColor {
        NSColor(red: redTrailR, green: redTrailG, blue: redTrailB, alpha: 1.0)
    }

    var blueTrailNSColor: NSColor {
        NSColor(red: blueTrailR, green: blueTrailG, blue: blueTrailB, alpha: 1.0)
    }

    // MARK: - Persistence

    private enum Keys {
        static let maxWidth = "trail.maxWidth"
        static let blueWidthMultiplier = "trail.blueWidthMultiplier"
        static let movementThreshold = "trail.movementThreshold"
        static let minimumVelocity = "trail.minimumVelocity"
        static let redFadeTime = "trail.redFadeTime"
        static let blueFadeTime = "trail.blueFadeTime"
        static let blueOuterOpacity = "trail.blueOuterOpacity"
        static let blueMiddleOpacity = "trail.blueMiddleOpacity"
        static let redTrailR = "trail.redTrailR"
        static let redTrailG = "trail.redTrailG"
        static let redTrailB = "trail.redTrailB"
        static let blueTrailR = "trail.blueTrailR"
        static let blueTrailG = "trail.blueTrailG"
        static let blueTrailB = "trail.blueTrailB"
        static let isTrailVisible = "trail.isTrailVisible"
        static let isRippleEnabled = "trail.isRippleEnabled"
    }

    private var isSuppressingCallbacks = false

    func save() {
        guard !isSuppressingCallbacks else { return }
        let d = UserDefaults.standard
        d.set(maxWidth, forKey: Keys.maxWidth)
        d.set(blueWidthMultiplier, forKey: Keys.blueWidthMultiplier)
        d.set(movementThreshold, forKey: Keys.movementThreshold)
        d.set(minimumVelocity, forKey: Keys.minimumVelocity)
        d.set(redFadeTime, forKey: Keys.redFadeTime)
        d.set(blueFadeTime, forKey: Keys.blueFadeTime)
        d.set(blueOuterOpacity, forKey: Keys.blueOuterOpacity)
        d.set(blueMiddleOpacity, forKey: Keys.blueMiddleOpacity)
        d.set(redTrailR, forKey: Keys.redTrailR)
        d.set(redTrailG, forKey: Keys.redTrailG)
        d.set(redTrailB, forKey: Keys.redTrailB)
        d.set(blueTrailR, forKey: Keys.blueTrailR)
        d.set(blueTrailG, forKey: Keys.blueTrailG)
        d.set(blueTrailB, forKey: Keys.blueTrailB)
        d.set(isTrailVisible, forKey: Keys.isTrailVisible)
        d.set(isRippleEnabled, forKey: Keys.isRippleEnabled)
    }

    func restore() {
        let d = UserDefaults.standard
        isSuppressingCallbacks = true
        defer {
            isSuppressingCallbacks = false
            onChanged?()
            onVisibilityChanged?()
        }

        if d.object(forKey: Keys.maxWidth) != nil { maxWidth = d.double(forKey: Keys.maxWidth) }
        if d.object(forKey: Keys.blueWidthMultiplier) != nil { blueWidthMultiplier = d.double(forKey: Keys.blueWidthMultiplier) }
        if d.object(forKey: Keys.movementThreshold) != nil { movementThreshold = d.double(forKey: Keys.movementThreshold) }
        if d.object(forKey: Keys.minimumVelocity) != nil { minimumVelocity = d.double(forKey: Keys.minimumVelocity) }
        if d.object(forKey: Keys.redFadeTime) != nil { redFadeTime = d.double(forKey: Keys.redFadeTime) }
        if d.object(forKey: Keys.blueFadeTime) != nil { blueFadeTime = d.double(forKey: Keys.blueFadeTime) }
        if d.object(forKey: Keys.blueOuterOpacity) != nil { blueOuterOpacity = d.double(forKey: Keys.blueOuterOpacity) }
        if d.object(forKey: Keys.blueMiddleOpacity) != nil { blueMiddleOpacity = d.double(forKey: Keys.blueMiddleOpacity) }
        if d.object(forKey: Keys.redTrailR) != nil { redTrailR = d.double(forKey: Keys.redTrailR) }
        if d.object(forKey: Keys.redTrailG) != nil { redTrailG = d.double(forKey: Keys.redTrailG) }
        if d.object(forKey: Keys.redTrailB) != nil { redTrailB = d.double(forKey: Keys.redTrailB) }
        if d.object(forKey: Keys.blueTrailR) != nil { blueTrailR = d.double(forKey: Keys.blueTrailR) }
        if d.object(forKey: Keys.blueTrailG) != nil { blueTrailG = d.double(forKey: Keys.blueTrailG) }
        if d.object(forKey: Keys.blueTrailB) != nil { blueTrailB = d.double(forKey: Keys.blueTrailB) }
        if d.object(forKey: Keys.isTrailVisible) != nil { isTrailVisible = d.bool(forKey: Keys.isTrailVisible) }
        if d.object(forKey: Keys.isRippleEnabled) != nil { isRippleEnabled = d.bool(forKey: Keys.isRippleEnabled) }
    }

    func resetToDefaults() {
        isSuppressingCallbacks = true
        maxWidth = 8.0
        blueWidthMultiplier = 3.5
        movementThreshold = 30.0
        minimumVelocity = 0.0
        redFadeTime = 0.6
        blueFadeTime = 0.35
        blueOuterOpacity = 0.02
        blueMiddleOpacity = 0.08
        redTrailR = 1.0
        redTrailG = 0.15
        redTrailB = 0.1
        blueTrailR = 0.1
        blueTrailG = 0.5
        blueTrailB = 1.0
        isTrailVisible = true
        isRippleEnabled = false
        isSuppressingCallbacks = false
        save()
        onChanged?()
        onVisibilityChanged?()
    }
}
