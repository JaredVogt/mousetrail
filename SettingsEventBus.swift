import Cocoa

/// Actions the settings UI needs to invoke on the surrounding application.
/// Implemented by `AppDelegate`; injected into `MenuBarSettingsView` to
/// replace ~10 raw closures.
protocol SettingsEventBus: AnyObject {
    func requestScreenRecordingPermission()
    func requestAccessibilityPermission()
    func startInfoUpdates()
    func stopInfoUpdates()
    func showHelpWindow()
    func restart()

    /// Read the current gesture router. Returns a fresh default if the
    /// backing app delegate is gone.
    func currentGestureRouter() -> GestureRouter
    /// Replace the gesture router and persist the change.
    func updateGestureRouter(_ router: GestureRouter)

    /// Active calibration session, or nil if none is running.
    func currentCalibrationSession() -> CalibrationSession?
    /// Start a fresh calibration session and return it.
    func startCalibration() -> CalibrationSession
}

/// Default restart — launches a new copy of the current binary and quits.
/// Lives on the protocol so conformers don't have to re-implement it.
extension SettingsEventBus {
    func restart() {
        guard let bundlePath = Bundle.main.executablePath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundlePath)
        try? process.run()
        NSApplication.shared.terminate(nil)
    }
}
