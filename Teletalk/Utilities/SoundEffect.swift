import AppKit

enum SoundEffect {
    case startRecording
    case stopRecording

    func play() {
        switch self {
        case .startRecording:
            let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/AssistantServices.framework/Versions/A/Resources/dt-begin.caf")
            (NSSound(contentsOf: url, byReference: true) ?? NSSound(named: "Pop"))?.play()
        case .stopRecording:
            let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/AssistantServices.framework/Versions/A/Resources/dt-confirm.caf")
            (NSSound(contentsOf: url, byReference: true) ?? NSSound(named: "Tink"))?.play()
        }
    }
}

