import Foundation
import os

#if canImport(FoundationModels)
    import FoundationModels
#endif

@available(macOS 26, *)
@MainActor
final class AIPostProcessor {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "AIPostProcessor")

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            SystemLanguageModel.default.isAvailable
        #else
            false
        #endif
    }

    /// Process transcription through on-device LLM.
    /// Returns original text on any failure.
    func enhance(text: String, systemPrompt: String) async -> String {
        #if canImport(FoundationModels)
            do {
                let session = LanguageModelSession(
                    instructions: systemPrompt
                )
                let response = try await session.respond(
                    to: text,
                    options: GenerationOptions(sampling: .greedy)
                )
                let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else {
                    logger.warning("AI returned empty result, falling back to raw text")
                    return text
                }
                return result
            } catch {
                logger.error("AI enhancement failed: \(error.localizedDescription)")
                return text
            }
        #else
            return text
        #endif
    }
}
