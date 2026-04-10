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
                }
            )
        } label: {
            Image(systemName: "cursorarrow.rays")
        }
        .menuBarExtraStyle(.window)
    }
}
