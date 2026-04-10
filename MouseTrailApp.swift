import SwiftUI

@main
struct MouseTrailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarSettingsView(settings: appDelegate.settings)
        } label: {
            Image(systemName: "cursorarrow.rays")
        }
        .menuBarExtraStyle(.window)
    }
}
