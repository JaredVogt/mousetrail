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
                bus: appDelegate
            )
        } label: {
            Image(systemName: "cursorarrow.rays")
        }
        .menuBarExtraStyle(.window)
    }
}
