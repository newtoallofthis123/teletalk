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
                pillContent(tint: .blue) {
                    Image(systemName: "mic.fill")
                    WaveformBars(level: appState.audioLevel)
                    Text("Listening…")
                }
            case .transcribing:
                pillContent(tint: .secondary) {
                    BouncingDots()
                    Text("Transcribing…")
                }
            case .inserting:
                pillContent(tint: .green) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                    Text("Done")
                }
            case .error(let message):
                pillContent(tint: .red) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .lineLimit(1)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: appState.recordingState)
    }

    private func pillContent<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(tint.opacity(0.12))
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Waveform Bars

/// 4 rounded bars that react to real-time audio level with smooth continuous interpolation.
struct WaveformBars: View {
    let level: Float

    private let barCount = 4
    private let barWidth: CGFloat = 3
    private let maxHeight: CGFloat = 16
    private let minHeight: CGFloat = 3

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let scale = barScale(for: index)
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(.primary)
                    .frame(width: barWidth, height: minHeight + (maxHeight - minHeight) * scale)
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: level)
            }
        }
    }

    /// Each bar gets a slightly different scale based on its index to create visual variation.
    private func barScale(for index: Int) -> CGFloat {
        let base = CGFloat(level)
        let offsets: [CGFloat] = [0.0, 0.3, 0.15, 0.45]
        let offset = offsets[index % offsets.count]
        // Use sin to create variation between bars
        let varied = base * (0.5 + 0.5 * sin(.pi * (base * 3 + offset * .pi * 2)))
        return max(0, min(1, varied))
    }
}

// MARK: - Bouncing Dots

/// 3 dots with staggered bounce animation for the transcribing state.
struct BouncingDots: View {
    @State private var animating = false

    private let dotSize: CGFloat = 5
    private let dotCount = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(.primary)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: animating ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
