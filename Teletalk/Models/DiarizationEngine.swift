import FluidAudio
import Foundation
import os

/// Wraps FluidAudio's OfflineDiarizerManager for speaker diarization.
@MainActor
@Observable
final class DiarizationEngine {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "DiarizationEngine")

    private var diarizer: OfflineDiarizerManager?

    enum State: Equatable {
        case idle
        case preparingModels
        case ready
        case processing
        case error(String)
    }

    private(set) var state: State = .idle

    /// Prepare diarization models (downloads from HuggingFace if needed).
    /// Call when user enables diarization.
    func prepareModels() async throws {
        state = .preparingModels
        do {
            let manager = OfflineDiarizerManager()
            try await manager.prepareModels()
            diarizer = manager
            state = .ready
            logger.info("Diarization models ready")
        } catch {
            state = .error(error.localizedDescription)
            logger.error("Failed to prepare diarization models: \(error)")
            throw error
        }
    }

    /// Process audio samples (16kHz mono Float32) and return diarization result.
    func process(audio samples: [Float]) async throws -> DiarizationResult {
        guard state == .ready, let diarizer else {
            throw DiarizationError.notReady
        }
        state = .processing
        do {
            let result = try await diarizer.process(audio: samples)
            state = .ready
            logger.info("Diarization complete: \(result.segments.count) segments")
            return result
        } catch {
            state = .ready
            logger.error("Diarization failed: \(error)")
            throw error
        }
    }

    /// Release diarizer resources when feature is disabled.
    func teardown() {
        diarizer = nil
        state = .idle
        logger.info("Diarization engine torn down")
    }
}

// MARK: - Errors

enum DiarizationError: LocalizedError {
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Diarization engine not ready"
        }
    }
}
