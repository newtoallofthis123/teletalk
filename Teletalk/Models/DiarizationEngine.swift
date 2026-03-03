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

// MARK: - Speaker Alignment

/// Aligns ASR token timings with diarization speaker segments.
/// Returns speaker-attributed text and optional SpeakerSegments for history.
/// Single-speaker results return plain text with nil segments (no labels).
func formatSpeakerAttributedText(
    asrText: String,
    tokenTimings: [TokenTiming]?,
    diarizationResult: DiarizationResult
) -> (text: String, segments: [SpeakerSegment]?) {
    guard let tokenTimings, !tokenTimings.isEmpty else {
        return (asrText, nil)
    }

    let speakerSegments = diarizationResult.segments
    guard !speakerSegments.isEmpty else {
        return (asrText, nil)
    }

    // Assign each token to the speaker with max time overlap
    let tokenSpeakers = tokenTimings.map { timing -> String? in
        var bestSpeaker: String?
        var bestOverlap: Float = 0
        let tokenStart = Float(timing.startTime)
        let tokenEnd = Float(timing.endTime)

        for segment in speakerSegments {
            let overlapStart = max(tokenStart, segment.startTimeSeconds)
            let overlapEnd = min(tokenEnd, segment.endTimeSeconds)
            let overlap = max(0, overlapEnd - overlapStart)
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = segment.speakerId
            }
        }

        // Fallback: assign to nearest segment if no overlap
        if bestSpeaker == nil {
            let tokenMid = (tokenStart + tokenEnd) / 2
            bestSpeaker = speakerSegments.min(by: { a, b in
                let distA = min(abs(a.startTimeSeconds - tokenMid), abs(a.endTimeSeconds - tokenMid))
                let distB = min(abs(b.startTimeSeconds - tokenMid), abs(b.endTimeSeconds - tokenMid))
                return distA < distB
            })?.speakerId
        }

        return bestSpeaker
    }

    // Check unique speakers — if only 1, suppress labels
    let uniqueSpeakers = Set(tokenSpeakers.compactMap { $0 })
    if uniqueSpeakers.count <= 1 {
        return (asrText, nil)
    }

    // Renumber speakers by order of first appearance
    var speakerNumberMap: [String: Int] = [:]
    var nextNumber = 1
    for speaker in tokenSpeakers {
        guard let speaker, speakerNumberMap[speaker] == nil else { continue }
        speakerNumberMap[speaker] = nextNumber
        nextNumber += 1
    }

    // Group consecutive same-speaker tokens into runs
    struct SpeakerRun {
        let speakerNumber: Int
        var tokens: [String]
        let startTime: Float
        var endTime: Float
    }

    var runs: [SpeakerRun] = []
    for (index, timing) in tokenTimings.enumerated() {
        let speaker = tokenSpeakers[index]
        let number = speaker.flatMap { speakerNumberMap[$0] } ?? 0

        if let last = runs.last, last.speakerNumber == number {
            runs[runs.count - 1].tokens.append(timing.token)
            runs[runs.count - 1].endTime = Float(timing.endTime)
        } else {
            runs.append(SpeakerRun(
                speakerNumber: number,
                tokens: [timing.token],
                startTime: Float(timing.startTime),
                endTime: Float(timing.endTime)
            ))
        }
    }

    // Build formatted text and SpeakerSegment array
    var formattedLines: [String] = []
    var resultSegments: [SpeakerSegment] = []

    for run in runs {
        // Tokens use SentencePiece convention: ▁ prefix = word boundary
        // Concatenate directly, then replace ▁ with space (matches FluidAudio's own decoding)
        let text = run.tokens.joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let label = "Speaker \(run.speakerNumber)"
        formattedLines.append("\(label): \(text)")
        resultSegments.append(SpeakerSegment(
            speaker: label,
            text: text,
            startTime: run.startTime,
            endTime: run.endTime
        ))
    }

    return (formattedLines.joined(separator: "\n"), resultSegments)
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
