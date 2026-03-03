import FluidAudio
import Foundation
import os

/// Wraps FluidAudio's AsrManager to transcribe audio samples into text.
final class TranscriptionEngine {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "TranscriptionEngine")

    private var asrManager: AsrManager?

    /// Initialize the engine with loaded models from ModelManager.
    /// Call once after ModelManager finishes loading.
    func initialize(models: AsrModels) async throws {
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        asrManager = manager

        logger.info("TranscriptionEngine initialized")
    }

    /// Transcribe audio samples (16kHz mono Float32 PCM) into an ASRResult.
    /// Returns nil if audio is too short or transcription is empty.
    func transcribe(samples: [Float]) async throws -> ASRResult? {
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

        return result
    }

    /// Configure vocabulary boosting with user's personal dictionary terms.
    func configureVocabulary(terms: [DictionaryTerm]) async throws {
        guard let asrManager else {
            throw TranscriptionError.notInitialized
        }

        guard !terms.isEmpty else {
            disableVocabulary()
            return
        }

        let vocabTerms = terms.map { term in
            CustomVocabularyTerm(
                text: term.text,
                aliases: term.aliases.isEmpty ? nil : term.aliases
            )
        }
        let context = CustomVocabularyContext(terms: vocabTerms)

        // Fix trailing commas in CTC model config.json (FluidAudio bug)
        let ctcCacheDir = CtcModels.defaultCacheDirectory(for: .ctc110m)
        fixTrailingCommasInJSON(directory: ctcCacheDir)

        let ctcModels = try await CtcModels.downloadAndLoad()

        try await asrManager.configureVocabularyBoosting(
            vocabulary: context,
            ctcModels: ctcModels
        )

        logger.info("Vocabulary boosting configured with \(terms.count) terms")
    }

    /// Fix trailing commas in JSON files that FluidAudio downloads with invalid JSON.
    private func fixTrailingCommasInJSON(directory: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "json" {
            guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let fixed = content.replacingOccurrences(
                of: #",(\s*[\]\}])"#,
                with: "$1",
                options: .regularExpression
            )
            if fixed != content {
                try? fixed.write(to: fileURL, atomically: true, encoding: .utf8)
                logger.info("Fixed trailing comma in \(fileURL.lastPathComponent)")
            }
        }
    }

    /// Disable vocabulary boosting.
    func disableVocabulary() {
        asrManager?.disableVocabularyBoosting()
        logger.info("Vocabulary boosting disabled")
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
