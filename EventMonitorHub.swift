import Cocoa

/// Owns the lifecycle of `NSEvent` global monitors. Returns opaque tokens so
/// callers can remove individual monitors; deinit tears down anything that's
/// still registered.
final class EventMonitorHub {
    typealias Token = UUID

    private var monitors: [Token: Any] = [:]

    @discardableResult
    func addGlobal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) -> Token? {
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) else {
            return nil
        }
        let token = Token()
        monitors[token] = monitor
        return token
    }

    func remove(_ token: Token) {
        guard let monitor = monitors.removeValue(forKey: token) else { return }
        NSEvent.removeMonitor(monitor)
    }

    func removeAll() {
        for monitor in monitors.values {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    deinit {
        removeAll()
    }
}
