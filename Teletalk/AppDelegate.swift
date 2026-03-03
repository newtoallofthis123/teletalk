import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            guard let appState else { return }
            appState.refreshPermissions()
            await appState.requestPermissionsOnLaunch()
        }
    }
}
