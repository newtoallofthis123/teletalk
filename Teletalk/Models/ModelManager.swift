import Foundation
import os
import FluidAudio

// MARK: - Model Types

enum ModelStatus: Equatable {
    case notDownloaded
    case downloading
    case downloaded
    case active
}

struct ModelInfo: Identifiable {
    let version: AsrModelVersion
    let displayName: String
    let languageDescription: String
    var status: ModelStatus = .notDownloaded
    var diskSize: Int64?

    var id: String {
        switch version {
        case .v2: return "v2"
        case .v3: return "v3"
        }
    }
}

// MARK: - ModelManager

/// Manages download, deletion, and switching of Parakeet TDT speech recognition models.
@MainActor
final class ModelManager {

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "ModelManager")

    private(set) var models: AsrModels?

    var availableModels: [ModelInfo] = [
        ModelInfo(version: .v2, displayName: "Parakeet TDT v2", languageDescription: "English"),
        ModelInfo(version: .v3, displayName: "Parakeet TDT v3", languageDescription: "25+ Languages"),
    ]

    var totalDiskUsage: Int64 {
        availableModels.compactMap(\.diskSize).reduce(0, +)
    }

    var loadedModels: AsrModels? { models }

    // MARK: - Lifecycle

    /// Loads the user's selected model on app launch.
    func loadModel(appState: AppState) async {
        guard appState.modelState != .ready else { return }

        let version = asrVersion(from: appState.selectedModelVersion)

        appState.modelState = .downloading(progress: -1)
        logger.info("Starting model download/load for \(appState.selectedModelVersion)…")

        do {
            updateStatus(for: version, to: .downloading)
            let loaded = try await AsrModels.downloadAndLoad(version: version)
            self.models = loaded

            updateStatus(for: version, to: .active)
            appState.modelState = .ready
            logger.info("Model loaded successfully")
        } catch {
            let message = error.localizedDescription
            updateStatus(for: version, to: .notDownloaded)
            appState.modelState = .error(message)
            logger.error("Model load failed: \(message)")
        }

        refreshDownloadStates()
        scanDiskUsage()
    }

    // MARK: - Download / Delete / Switch

    /// Download a specific model version without activating it.
    func downloadModel(version: AsrModelVersion) async throws {
        updateStatus(for: version, to: .downloading)
        do {
            _ = try await AsrModels.downloadAndLoad(version: version)
            updateStatus(for: version, to: .downloaded)
            scanDiskUsage()
        } catch {
            updateStatus(for: version, to: .notDownloaded)
            throw error
        }
    }

    /// Delete cached files for a model version.
    /// Cannot delete the currently active model.
    func deleteModel(version: AsrModelVersion) throws {
        guard statusFor(version) != .active else {
            throw ModelManagerError.cannotDeleteActiveModel
        }

        // defaultCacheDirectory returns ~/Library/Application Support/FluidAudio/Models/{folderName}/
        let cacheDir = AsrModels.defaultCacheDirectory(for: version)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            try FileManager.default.removeItem(at: cacheDir)
            logger.info("Deleted model cache at \(cacheDir.path)")
        }

        updateStatus(for: version, to: .notDownloaded)
        scanDiskUsage()
    }

    /// Switch the active model. Downloads if needed, then reinitializes TranscriptionEngine.
    /// Returns the loaded AsrModels for the caller to reinitialize TranscriptionEngine.
    func switchActiveModel(to version: AsrModelVersion, appState: AppState) async throws -> AsrModels {
        guard appState.recordingState == .idle else {
            throw ModelManagerError.cannotSwitchWhileRecording
        }

        appState.modelState = .downloading(progress: -1)

        // Mark old active as just downloaded
        if let oldActive = availableModels.first(where: { $0.status == .active }) {
            updateStatus(for: oldActive.version, to: .downloaded)
        }

        updateStatus(for: version, to: .downloading)

        do {
            let loaded = try await AsrModels.downloadAndLoad(version: version)
            self.models = loaded

            updateStatus(for: version, to: .active)
            appState.selectedModelVersion = version == .v2 ? "v2" : "v3"
            appState.modelState = .ready

            refreshDownloadStates()
            scanDiskUsage()
            logger.info("Switched to model \(version == .v2 ? "v2" : "v3")")
            return loaded
        } catch {
            appState.modelState = .error(error.localizedDescription)
            updateStatus(for: version, to: .notDownloaded)
            refreshDownloadStates()
            throw error
        }
    }

    // MARK: - Disk Usage

    func scanDiskUsage() {
        for i in availableModels.indices {
            let version = availableModels[i].version
            let cacheDir = AsrModels.defaultCacheDirectory(for: version)
            availableModels[i].diskSize = directorySize(at: cacheDir)
        }
    }

    /// Returns the FluidAudio models storage root directory.
    var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: - Helpers

    func refreshDownloadStates() {
        for i in availableModels.indices {
            let version = availableModels[i].version
            // Don't overwrite active or downloading states
            if availableModels[i].status == .active || availableModels[i].status == .downloading {
                continue
            }
            let cacheDir = AsrModels.defaultCacheDirectory(for: version)
            if AsrModels.modelsExist(at: cacheDir, version: version) {
                availableModels[i].status = .downloaded
            } else {
                availableModels[i].status = .notDownloaded
            }
        }
    }

    private func updateStatus(for version: AsrModelVersion, to status: ModelStatus) {
        guard let idx = availableModels.firstIndex(where: { $0.version == version }) else { return }
        availableModels[idx].status = status
    }

    private func statusFor(_ version: AsrModelVersion) -> ModelStatus? {
        availableModels.first(where: { $0.version == version })?.status
    }

    private func asrVersion(from string: String) -> AsrModelVersion {
        string == "v3" ? .v3 : .v2
    }

    private func directorySize(at url: URL) -> Int64? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total > 0 ? total : nil
    }
}

// MARK: - Errors

enum ModelManagerError: LocalizedError {
    case cannotDeleteActiveModel
    case cannotSwitchWhileRecording

    var errorDescription: String? {
        switch self {
        case .cannotDeleteActiveModel:
            return "Cannot delete the active model"
        case .cannotSwitchWhileRecording:
            return "Cannot switch models while recording"
        }
    }
}

// MARK: - AsrModelVersion Identifiers

extension AsrModelVersion {
    var displayId: String {
        switch self {
        case .v2: return "v2"
        case .v3: return "v3"
        }
    }
}
