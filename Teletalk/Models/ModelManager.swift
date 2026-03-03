import Foundation
import os
import FluidAudio

/// Manages download and lifecycle of the Parakeet TDT speech recognition model.
///
/// Uses FluidAudio's `AsrModels.downloadAndLoad()` which handles HuggingFace download,
/// caching in Application Support, and CoreML compilation automatically.
@MainActor
final class ModelManager {

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "ModelManager")

    private var models: AsrModels?

    /// Loads the Parakeet TDT v2 model, updating appState throughout.
    /// Call on app launch after permissions are granted.
    func loadModel(appState: AppState) async {
        guard appState.modelState != .ready else { return }

        appState.modelState = .downloading(progress: 0)
        logger.info("Starting model download/load…")

        do {
            appState.modelState = .downloading(progress: -1)

            let models = try await AsrModels.downloadAndLoad(version: .v2)
            self.models = models

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
        appState.modelState = .notDownloaded
        await loadModel(appState: appState)
    }

    var loadedModels: AsrModels? { models }
}
