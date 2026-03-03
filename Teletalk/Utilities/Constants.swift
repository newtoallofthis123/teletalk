import Foundation

enum Constants {
    static let appName = "TeleTalk"
    static let bundleIdentifier = "com.teletalk.app"

    // MARK: - Storage

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TeleTalk/Models", isDirectory: true)
    }()

    // MARK: - UserDefaults Keys

    enum Defaults {
        static let hasCompletedSetup = "hasCompletedSetup"
        // Hotkeys
        static let toggleShortcutEnabled = "toggleShortcutEnabled"
        static let holdShortcutEnabled = "holdShortcutEnabled"
        // Audio
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let maxRecordingDuration = "maxRecordingDuration"
        static let minRecordingDuration = "minRecordingDuration"
        // Models
        static let selectedModelVersion = "selectedModelVersion"
        // General
        static let insertionMethod = "insertionMethod"
        static let showOverlay = "showOverlay"
        static let overlayPosition = "overlayPosition"
    }

    // MARK: - Audio

    enum Audio {
        static let sampleRate: Double = 16_000
    }

    // MARK: - UI

    enum UI {
        static let overlayFadeOutDuration: TimeInterval = 0.6
        static let errorDisplayDuration: TimeInterval = 2.0
        static let overlayBottomOffset: CGFloat = 100
    }
}
