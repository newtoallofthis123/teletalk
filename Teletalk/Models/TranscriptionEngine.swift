import Foundation
import os
import FluidAudio

/// Wraps FluidAudio's AsrManager to transcribe audio samples into text.
final class TranscriptionEngine {

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "TranscriptionEngine")

    private var asrManager: AsrManager?

    /// Initialize the engine with loaded models from ModelManager.
    /// Call once after ModelManager finishes loading.
    func initialize(models: AsrModels) async throws {
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        self.asrManager = manager

        logger.info("TranscriptionEngine initialized")
    }

    /// Transcribe audio samples (16kHz mono Float32 PCM) into text.
    /// Returns nil if audio is too short or transcription is empty.
    func transcribe(samples: [Float]) async throws -> String? {
        guard let asrManager else {
            throw TranscriptionError.notInitialized
        }

        guard samples.count >= 3200 else {
            logger.debug("Audio too short (\(samples.count) samples), discarding")
            return nil
        }

        let start = ContinuousClock.now

        let result = try await asrManager.transcribe(samples, source: .system)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let elapsed = ContinuousClock.now - start
        logger.info("Transcription completed in \(elapsed)")

        guard !text.isEmpty else {
            logger.debug("Transcription returned empty text")
            return nil
        }

        return text
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Transcription engine not initialized"
        }
    }
}
