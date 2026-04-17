import Cocoa
import QuartzCore

/// Produces ticks for the animation loop. `start` begins driving callbacks;
/// `stop` halts them. Safe to call `stop` repeatedly.
protocol AnimationDriver: AnyObject {
    func start(onTick: @escaping () -> Void)
    func stop()
}

/// Vsync-synchronized driver. Requires macOS 14+ and an already-visible
/// `NSWindow` to derive the display link from.
@available(macOS 14.0, *)
final class DisplayLinkDriver: NSObject, AnimationDriver {
    private weak var window: NSWindow?
    private var displayLink: CADisplayLink?
    private var tickHandler: (() -> Void)?

    init(window: NSWindow) {
        self.window = window
    }

    func start(onTick: @escaping () -> Void) {
        stop()
        guard let window else { return }
        let link = window.displayLink(target: self, selector: #selector(handleTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        tickHandler = onTick
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        tickHandler = nil
    }

    @objc private func handleTick(_ link: CADisplayLink) {
        tickHandler?()
    }
}

/// 60 Hz `Timer` fallback when display links aren't available.
final class TimerDriver: AnimationDriver {
    private var timer: Timer?

    func start(onTick: @escaping () -> Void) {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            onTick()
        }
        timer.tolerance = 1.0 / 120.0  // half a frame at 60Hz — lets the OS batch wakeups
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
