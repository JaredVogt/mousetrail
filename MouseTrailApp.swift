import SwiftUI

@main
struct MouseTrailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarSettingsView(
                settings: appDelegate.settings,
                liveInfo: appDelegate.liveInfo,
                presetManager: appDelegate.presetManager,
                onRequestPermission: { [weak appDelegate] in
                    appDelegate?.requestScreenRecordingPermission()
                },
                onRequestAccessibility: { [weak appDelegate] in
                    appDelegate?.requestAccessibilityPermission()
                },
                onStartInfoUpdates: { [weak appDelegate] in
                    appDelegate?.startInfoUpdates()
                },
                onStopInfoUpdates: { [weak appDelegate] in
                    appDelegate?.stopInfoUpdates()
                },
                onShowHelp: { [weak appDelegate] in
                    appDelegate?.showHelpWindow()
                },
                onRestart: {
                    guard let bundlePath = Bundle.main.executablePath else { return }
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: bundlePath)
                    try? process.run()
                    NSApplication.shared.terminate(nil)
                },
                getGestureRouter: { [weak appDelegate] in
                    appDelegate?.gestureRouter ?? GestureRouter(shakeZones: [], circleConfig: CircleGestureConfig())
                },
                setGestureRouter: { [weak appDelegate] router in
                    appDelegate?.gestureRouter = router
                    appDelegate?.saveGestureSettings()
                },
                getCalibrationSession: { [weak appDelegate] in
                    appDelegate?.calibrationSession
                },
                startCalibration: { [weak appDelegate] in
                    let session = CalibrationSession()
                    appDelegate?.calibrationSession = session
                    return session
                }
            )
        } label: {
            Image(systemName: "cursorarrow.rays")
        }
        .menuBarExtraStyle(.window)
    }
}
