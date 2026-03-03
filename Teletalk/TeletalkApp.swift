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

        Window("TeleTalk Settings", id: "settings") {
            SettingsView()
                .environment(appDelegate.appState)
                .environment(appDelegate.modelManager)
                .environment(appDelegate.audioDeviceEnumerator)
                .environment(appDelegate.transcriptionHistory)
                .environment(appDelegate.personalDictionary)
                .environment(appDelegate.textShortcutManager)
        }
        .defaultSize(width: 500, height: 450)
        .windowResizability(.contentSize)
    }
}
