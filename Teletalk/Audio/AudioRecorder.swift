import AVFoundation
import os

/// Records audio from the microphone using AVAudioEngine.
/// Outputs 16kHz mono Float32 PCM samples suitable for Parakeet TDT.
@MainActor
final class AudioRecorder {

    enum State: Equatable {
        case idle
        case recording
    }

    private(set) var state: State = .idle

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "AudioRecorder")
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var recordingStartTime: Date?

    /// Starts recording from the default input device.
    /// Accumulates 16kHz mono Float32 samples into an internal buffer.
    func startRecording() throws {
        guard state == .idle else {
            logger.warning("startRecording called while already recording")
            return
        }

        samples.removeAll()
        recordingStartTime = Date()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz, mono, Float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Constants.Audio.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.formatCreationFailed
        }

        // Use a converter if the hardware format differs from our target
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }

        let bufferSize = AVAudioFrameCount(4096)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
        state = .recording
        logger.info("Recording started (input: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch)")
    }

    /// Stops recording and returns accumulated samples.
    /// Returns `nil` if the recording was too short (< 200ms).
    func stopRecording() -> [Float]? {
        guard state == .recording else {
            logger.warning("stopRecording called while not recording")
            return nil
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = .idle

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        logger.info("Recording stopped — \(String(format: "%.1f", duration))s, \(self.samples.count) samples")

        // Discard accidental taps
        if duration < Constants.Audio.minimumRecordingDuration {
            logger.info("Recording too short (\(String(format: "%.0f", duration * 1000))ms), discarding")
            samples.removeAll()
            return nil
        }

        let result = samples
        samples.removeAll()
        return result
    }

    // MARK: - Private

    private nonisolated func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)
        ) + 1

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            Task { @MainActor in
                logger.error("Audio conversion error: \(error.localizedDescription)")
            }
            return
        }

        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let count = Int(convertedBuffer.frameLength)
        let newSamples = Array(UnsafeBufferPointer(start: channelData, count: count))

        Task { @MainActor [weak self] in
            self?.samples.append(contentsOf: newSamples)
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create target audio format"
        case .converterCreationFailed:
            return "Failed to create audio format converter"
        }
    }
}
