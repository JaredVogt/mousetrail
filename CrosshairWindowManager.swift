import Cocoa

/// Owns the per-screen crosshair overlay windows + views. Crosshair stays on
/// full-screen overlays because its lines span the entire display, and it has
/// no shadow blur so the cost is negligible regardless of resolution.
final class CrosshairWindowManager {
    private(set) var windows: [NSPanel] = []
    private(set) var views: [CrosshairView] = []

    func rebuild(initiallyVisible: Bool, configureView: (CrosshairView) -> Void) {
        cleanup()

        for screen in NSScreen.screens {
            let screenFrame = screen.frame

            let window = NSPanel(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .transient,
                .ignoresCycle,
                .stationary
            ]
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false

            let viewBounds = NSRect(x: 0, y: 0, width: screenFrame.width, height: screenFrame.height)
            let view = CrosshairView(frame: viewBounds)
            view.wantsLayer = true
            configureView(view)

            window.contentView = view

            if initiallyVisible {
                window.orderFront(nil)
            }

            windows.append(window)
            views.append(view)
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

    func clearAll() {
        for view in views {
            view.clear()
        }
    }

    func cleanup() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
        views.removeAll()
    }
}
