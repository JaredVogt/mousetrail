import Cocoa

/// Owns the trail overlay window + view. Now backed by a single
/// MouseFollowingWindow that's small and tracks the cursor, so layer-shadow
/// blur cost no longer scales with screen resolution. Storage stays as arrays
/// (count: 0 or 1) so call sites that iterate continue to work unchanged.
final class TrailWindowManager {
    private(set) var windows: [NSPanel] = []
    private(set) var views: [TrailView] = []

    /// Trail views that received content recently and still need rendering.
    var dirtyIndices: Set<Int> = []

    /// Typed accessor for the (single) cursor-following trail window.
    var trailWindow: MouseFollowingWindow? {
        windows.first as? MouseFollowingWindow
    }

    /// Tear down existing overlay and create a fresh one. `configureView` is
    /// called once on the new view so the caller can apply settings-derived
    /// state.
    func rebuild(initiallyVisible: Bool, configureView: (TrailView) -> Void) {
        cleanup()

        let window = MouseFollowingWindow()
        let viewBounds = NSRect(origin: .zero, size: window.frame.size)
        let trailView = TrailView(frame: viewBounds)
        trailView.wantsLayer = true
        configureView(trailView)
        window.contentView = trailView

        if initiallyVisible {
            window.orderFront(nil)
        }

        windows.append(window)
        views.append(trailView)
    }

    func showWindows(_ show: Bool) {
        for window in windows {
            if show {
                window.orderFront(nil)
            } else {
                window.orderOut(nil)
            }
        }
    }

    func resetAllTrails() {
        for view in views {
            view.resetTrail()
        }
    }

    /// Mark every trail view that still has fading content as dirty.
    func markVisibleDirty(at now: TimeInterval) {
        for (index, view) in views.enumerated() where view.hasVisiblePoints(at: now) {
            dirtyIndices.insert(index)
        }
    }

    func cleanup() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
        views.removeAll()
        dirtyIndices.removeAll()
    }
}
