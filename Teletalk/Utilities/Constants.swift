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
        static let hotkeyMode = "hotkeyMode" // "holdToTalk" or "toggle"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
    }

    // MARK: - Audio

    enum Audio {
        static let sampleRate: Double = 16_000
        static let minimumRecordingDuration: TimeInterval = 0.2 // seconds
        static let maximumRecordingDuration: TimeInterval = 120 // 2 minutes
    }

    // MARK: - UI

    enum UI {
        static let overlayFadeOutDuration: TimeInterval = 0.3
        static let errorDisplayDuration: TimeInterval = 2.0
        static let overlayBottomOffset: CGFloat = 100
    }
}
