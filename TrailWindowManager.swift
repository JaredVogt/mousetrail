import Cocoa

/// Owns the per-screen trail overlay windows + views, their dirty set, and
/// the teardown/rebuild that runs when the screen configuration changes.
///
/// AppDelegate calls `rebuild` with a configurator closure supplying per-view
/// settings, and drives updates through `forEachView` / `markVisibleDirty`.
final class TrailWindowManager {
    private(set) var windows: [NSPanel] = []
    private(set) var views: [TrailView] = []

    /// Trail views that received content recently and still need rendering.
    var dirtyIndices: Set<Int> = []

    /// Tear down existing overlays and create fresh ones for the current
    /// screen configuration. `configureView` is called once per newly created
    /// view so the caller can apply settings-derived state.
    func rebuild(initiallyVisible: Bool, configureView: (TrailView) -> Void) {
        cleanup()

        for screen in NSScreen.screens {
            let screenFrame = screen.frame

            let trailWindow = NSPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            trailWindow.isOpaque = false
            trailWindow.backgroundColor = .clear
            trailWindow.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
            trailWindow.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .transient,
                .ignoresCycle,
                .stationary
            ]
            trailWindow.hidesOnDeactivate = false
            trailWindow.ignoresMouseEvents = true
            trailWindow.hasShadow = false
            trailWindow.isReleasedWhenClosed = false

            let viewBounds = NSRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
            let trailView = TrailView(frame: viewBounds)
            trailView.wantsLayer = true
            configureView(trailView)

            trailWindow.contentView = trailView

            if initiallyVisible {
                trailWindow.orderFront(nil)
            }

            windows.append(trailWindow)
            views.append(trailView)
        }
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
