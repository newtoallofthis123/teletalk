import AudioToolbox
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

    /// Called when recording is auto-stopped (max duration or mic disconnection).
    var onAutoStop: (() -> Void)?

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "AudioRecorder")
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var recordingStartTime: Date?
    private var maxDurationTask: Task<Void, Never>?
    private var configObserver: Any?
    private var maxDuration: TimeInterval = 120
    private var minDuration: TimeInterval = 0.2

    /// Starts recording from the specified audio device (or system default if nil).
    /// Accumulates 16kHz mono Float32 samples into an internal buffer.
    func startRecording(deviceUID: String? = nil, maxDuration: TimeInterval = 120, minDuration: TimeInterval = 0.2) throws {
        guard state == .idle else {
            logger.warning("startRecording called while already recording")
            return
        }

        self.maxDuration = maxDuration
        self.minDuration = minDuration
        samples.removeAll()
        recordingStartTime = Date()

        let inputNode = engine.inputNode

        // Set specific audio device if requested
        if let deviceUID {
            setAudioDevice(uid: deviceUID, on: inputNode)
        }

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

        // Auto-stop after max duration
        maxDurationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.maxDuration))
            guard self.state == .recording else { return }
            self.logger.warning("Max recording duration reached, auto-stopping")
            self.onAutoStop?()
        }

        // Watch for audio hardware changes (mic disconnect)
        observeAudioConfigChanges()
    }

    /// Stops recording and returns accumulated samples.
    /// Returns `nil` if the recording was too short (< 200ms).
    func stopRecording() -> [Float]? {
        guard state == .recording else {
            logger.warning("stopRecording called while not recording")
            return nil
        }

        maxDurationTask?.cancel()
        maxDurationTask = nil
        removeAudioConfigObserver()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = .idle

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        logger.info("Recording stopped — \(String(format: "%.1f", duration))s, \(self.samples.count) samples")

        // Discard accidental taps
        if duration < minDuration {
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

    private func observeAudioConfigChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                self.logger.warning("Audio configuration changed (mic disconnected?), auto-stopping")
                self.onAutoStop?()
            }
        }
    }

    /// Sets a specific audio input device on the engine's input node by UID.
    private func setAudioDevice(uid: String, on inputNode: AVAudioInputNode) {
        guard let audioUnit = inputNode.audioUnit else {
            logger.warning("Could not get AudioUnit from input node")
            return
        }

        // Resolve UID → AudioDeviceID by scanning all devices
        guard var deviceID = resolveDeviceID(forUID: uid) else {
            logger.warning("Could not resolve device UID \(uid), using default")
            return
        }

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            logger.warning("Failed to set audio device \(uid): \(status), falling back to default")
        } else {
            logger.info("Set audio input device to \(uid)")
        }
    }

    /// Resolves a device UID string to an AudioDeviceID by scanning all devices.
    private func resolveDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return nil }

        for deviceID in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var deviceUIDRef: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            if AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &deviceUIDRef) == noErr,
               (deviceUIDRef as String) == uid {
                return deviceID
            }
        }
        return nil
    }

    private func removeAudioConfigObserver() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case formatCreationFailed
    case converterCreationFailed
    case micDisconnected

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create target audio format"
        case .converterCreationFailed:
            return "Failed to create audio format converter"
        case .micDisconnected:
            return "Microphone was disconnected"
        }
    }
}
