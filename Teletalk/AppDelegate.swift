import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let modelManager = ModelManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            print("[TeleTalk] Requesting permissions...")
            await appState.requestPermissionsOnLaunch()
            print("[TeleTalk] Mic permission result: \(appState.permissions.microphone)")

            if appState.permissions.microphone == .granted {
                await modelManager.loadModel(appState: appState)
            }
        }
    }
}
