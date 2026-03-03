import SwiftUI

@main
struct TeletalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("TeleTalk", systemImage: "mic.fill") {
            MenuBarView()
        }

        Settings {
            SettingsView()
        }
    }
}
