import Foundation
import os

// NOTE: Uncomment FluidAudio import once SPM dependency is added in Xcode.
// import FluidAudio

/// Manages download and lifecycle of the Parakeet TDT speech recognition model.
///
/// Uses FluidAudio's `AsrModels.downloadAndLoad()` which handles HuggingFace download,
/// caching in Application Support, and CoreML compilation automatically.
@MainActor
final class ModelManager {

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "ModelManager")

    // Once FluidAudio is added, uncomment:
    // private var models: AsrModels?

    /// Loads the Parakeet TDT v2 model, updating appState throughout.
    /// Call on app launch after permissions are granted.
    func loadModel(appState: AppState) async {
        guard appState.modelState != .ready else { return }

        appState.modelState = .downloading(progress: 0)
        logger.info("Starting model download/load…")

        do {
            // FluidAudio handles download (if needed) + CoreML compilation + loading.
            // Progress reporting is built into AsrModels — for now we jump to indeterminate.
            appState.modelState = .downloading(progress: -1) // indeterminate until FluidAudio provides progress

            // TODO: Uncomment when FluidAudio SPM dependency is added:
            // let models = try await AsrModels.downloadAndLoad(version: .v2)
            // self.models = models

            // Placeholder: simulate load for build verification
            try await Task.sleep(for: .seconds(0.1))

            appState.modelState = .ready
            logger.info("Model loaded successfully")
        } catch {
            let message = error.localizedDescription
            appState.modelState = .error(message)
            logger.error("Model load failed: \(message)")
        }
    }

    /// Re-download the model (e.g., after corruption).
    func redownloadModel(appState: AppState) async {
        // Reset state and re-trigger
        appState.modelState = .notDownloaded

        // TODO: Uncomment when FluidAudio SPM dependency is added:
        // Clear cached model files if needed
        // try? FileManager.default.removeItem(at: Constants.modelsDirectory)

        await loadModel(appState: appState)
    }

    // Once FluidAudio is added, expose models for TranscriptionEngine:
    // var loadedModels: AsrModels? { models }
}
