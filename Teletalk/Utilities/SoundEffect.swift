import AppKit

enum SoundEffect {
    case startRecording
    case stopRecording

    func play() {
        switch self {
        case .startRecording:
            NSSound(named: "Tink")?.play()
        case .stopRecording:
            NSSound(named: "Pop")?.play()
        }
    }
}
