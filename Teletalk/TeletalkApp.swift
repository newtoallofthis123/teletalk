import SwiftUI

@main
struct TeletalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    init() {
        appDelegate.appState = appState
    }

    var body: some Scene {
        MenuBarExtra("TeleTalk", systemImage: "mic.fill") {
            MenuBarView()
                .environment(appState)
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
