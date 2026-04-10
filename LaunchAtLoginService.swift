import ServiceManagement

@Observable
@MainActor
class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private(set) var isEnabled: Bool = false

    init() {
        updateStatus()
    }

    func updateStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            updateStatus()
        } catch {
            print("[debug] Failed to toggle launch at login: \(error)")
        }
    }
}
