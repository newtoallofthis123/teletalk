import Cocoa
import os
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let modelManager = ModelManager()

    private let audioRecorder = AudioRecorder()
    private let transcriptionEngine = TranscriptionEngine()
    private let textInserter = TextInserter()
    private var overlayWindow: OverlayWindow?
    private var hotkeyManager: HotkeyManager?
    private var setupWindow: NSWindow?

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        overlayWindow = OverlayWindow(appState: appState)

        audioRecorder.onAutoStop = { [weak self] in
            self?.stopPipeline()
        }

        Task { @MainActor in
            await appState.requestPermissionsOnLaunch()

            if appState.permissions.microphone == .granted {
                await modelManager.loadModel(appState: appState)
            }

            if appState.modelState == .ready, let models = modelManager.loadedModels {
                try? await transcriptionEngine.initialize(models: models)
            }

            setupHotkey()
            startPermissionMonitoring()

            // Show first-run setup if not completed
            if !UserDefaults.standard.bool(forKey: Constants.Defaults.hasCompletedSetup) {
                showSetupWindow()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState.refreshPermissions()
    }

    private func showSetupWindow() {
        let setupView = SetupView()
            .environment(appState)

        let hostingView = NSHostingView(rootView: setupView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TeleTalk Setup"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Keep a reference so the window isn't deallocated
        setupWindow = window
    }

    // MARK: - Permission Monitoring

    /// Periodically checks if permissions were revoked while the app is running.
    private func startPermissionMonitoring() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                let previousMic = appState.permissions.microphone
                appState.refreshPermissions()

                // If mic was revoked while recording, stop the pipeline
                if previousMic == .granted && appState.permissions.microphone == .denied {
                    logger.warning("Microphone permission revoked")
                    if audioRecorder.state == .recording {
                        stopPipeline()
                    }
                    showError("Mic permission revoked")
                }
            }
        }
    }

    // MARK: - Pipeline

    private func setupHotkey() {
        hotkeyManager = HotkeyManager(
            appState: appState,
            onStartRecording: { [weak self] in self?.startPipeline() },
            onStopRecording: { [weak self] in self?.stopPipeline() }
        )
        hotkeyManager?.register()
    }

    private func startPipeline() {
        guard appState.modelState == .ready else {
            logger.warning("Cannot record — model not ready")
            showError("Model not ready")
            return
        }

        do {
            try audioRecorder.startRecording()
            appState.recordingState = .listening
            overlayWindow?.show()
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            showError("Mic error")
        }
    }

    private func stopPipeline() {
        let samples = audioRecorder.stopRecording()

        guard let samples, !samples.isEmpty else {
            appState.recordingState = .idle
            overlayWindow?.hide()
            return
        }

        appState.recordingState = .transcribing

        Task { @MainActor in
            do {
                let text = try await transcriptionEngine.transcribe(samples: samples)

                guard let text, !text.isEmpty else {
                    logger.info("Nothing transcribed")
                    showError("Nothing heard")
                    return
                }

                appState.recordingState = .inserting
                await textInserter.insert(text: text)

                // Brief "Done" display, then hide
                try? await Task.sleep(for: .milliseconds(
                    Int(Constants.UI.overlayFadeOutDuration * 1000)
                ))
                appState.recordingState = .idle
                overlayWindow?.hide()
            } catch {
                logger.error("Transcription failed: \(error.localizedDescription)")
                showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        appState.recordingState = .error(message)
        overlayWindow?.show()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.UI.errorDisplayDuration))
            if case .error = appState.recordingState {
                appState.recordingState = .idle
                overlayWindow?.hide()
            }
        }
    }
}
