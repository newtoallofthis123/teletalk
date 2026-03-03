import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    let modelManager = ModelManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            guard let appState else { return }
            appState.refreshPermissions()
            await appState.requestPermissionsOnLaunch()

            // Load model after permissions are granted
            if appState.permissions.microphone == .granted {
                await modelManager.loadModel(appState: appState)
            }
        }
    }
}
