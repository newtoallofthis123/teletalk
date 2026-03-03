import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure no dock icon (LSUIElement should handle this, but belt-and-suspenders)
        NSApp.setActivationPolicy(.accessory)
    }
}
