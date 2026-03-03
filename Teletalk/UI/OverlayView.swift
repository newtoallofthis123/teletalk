import SwiftUI

/// SwiftUI pill overlay showing current transcription state.
struct OverlayView: View {

    let appState: AppState

    var body: some View {
        Group {
            switch appState.recordingState {
            case .idle:
                EmptyView()
            case .listening:
                pillContent {
                    Image(systemName: "mic.fill")
                        .symbolEffect(.pulse)
                    Text("Listening…")
                }
            case .transcribing:
                pillContent {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing…")
                }
            case .inserting:
                pillContent {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done")
                }
            case .error(let message):
                pillContent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .lineLimit(1)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.recordingState)
    }

    private func pillContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
