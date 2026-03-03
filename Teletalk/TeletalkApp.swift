import SwiftUI

@main
struct TeletalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("TeleTalk", systemImage: "mic.fill") {
            MenuBarView()
                .environment(appDelegate.appState)
                .environment(appDelegate.modelManager)
                .environment(appDelegate.audioDeviceEnumerator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.appState)
                .environment(appDelegate.modelManager)
                .environment(appDelegate.audioDeviceEnumerator)
        }
    }
}
