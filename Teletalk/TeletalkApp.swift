import SwiftUI

@main
struct TeletalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("TeleTalk", image: "MenuBarIcon") {
            MenuBarView()
                .environment(appDelegate.appState)
                .environment(appDelegate.modelManager)
                .environment(appDelegate.audioDeviceEnumerator)
                .environment(appDelegate.transcriptionHistory)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appDelegate.appState)
                .environment(appDelegate.modelManager)
                .environment(appDelegate.audioDeviceEnumerator)
                .environment(appDelegate.transcriptionHistory)
                .environment(appDelegate.personalDictionary)
        }
    }
}
