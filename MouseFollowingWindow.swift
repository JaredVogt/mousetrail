import Cocoa

/// A small borderless overlay panel that can be repositioned around a cursor
/// location. The trail renders into this instead of a full-screen overlay so
/// layer-shadow blur and compositor work don't scale with screen resolution.
final class MouseFollowingWindow: NSPanel {
    /// Edge length of the square overlay window in logical points. Larger
    /// than strictly necessary so the cursor has room to roam before the
    /// window has to be repositioned — every reposition risks a 1-frame
    /// visual jitter because window moves and layer updates aren't atomic.
    static let defaultSize: CGFloat = 2048

    /// How far the cursor can drift from the window center before we
    /// reposition. Picked so the trail tail (≈600 px at default settings)
    /// stays well inside the window: halfExtent (1024) − trailExtent (600)
    /// − safety margin = 256.
    static let repositionThreshold: CGFloat = 256

    init(size: CGFloat = MouseFollowingWindow.defaultSize) {
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
            .stationary
        ]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
    }

    /// Move the window so `screenPoint` sits at its center.
    func repositionAroundCursor(_ screenPoint: NSPoint) {
        let halfWidth = frame.width / 2
        let halfHeight = frame.height / 2
        setFrameOrigin(NSPoint(
            x: screenPoint.x - halfWidth,
            y: screenPoint.y - halfHeight
        ))
    }

    /// True when `screenPoint` has drifted further than `repositionThreshold`
    /// from the window's center, in which case the trail tail risks clipping
    /// at the window edge.
    func cursorOutsideSafeZone(_ screenPoint: NSPoint) -> Bool {
        let dx = screenPoint.x - frame.midX
        let dy = screenPoint.y - frame.midY
        return abs(dx) > Self.repositionThreshold || abs(dy) > Self.repositionThreshold
    }
}
