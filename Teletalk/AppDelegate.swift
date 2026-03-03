import Cocoa
import os
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let modelManager = ModelManager()
    let transcriptionHistory = TranscriptionHistory()
    let personalDictionary = PersonalDictionary()
    let textShortcutManager = TextShortcutManager()

    private let audioRecorder = AudioRecorder()
    let audioDeviceEnumerator = AudioDeviceEnumerator()
    private let transcriptionEngine = TranscriptionEngine()
    private let textInserter = TextInserter()
    private var overlayWindow: OverlayWindow?
    private var hotkeyManager: HotkeyManager?
    private var setupWindow: NSWindow?
    private var aiPostProcessor: Any?
    private var pipelineTask: Task<Void, Never>?

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        observeSettingsWindowClose()
        overlayWindow = OverlayWindow(appState: appState)

        audioRecorder.onAutoStop = { [weak self] in
            self?.stopPipeline()
        }
        audioRecorder.onAudioLevel = { [weak self] level in
            self?.appState.audioLevel = level
        }

        Task { @MainActor in
            await appState.requestPermissionsOnLaunch()

            if appState.permissions.microphone == .granted {
                await modelManager.loadModel(appState: appState)
            }

            if appState.modelState == .ready, let models = modelManager.loadedModels {
                try? await transcriptionEngine.initialize(models: models)

                // Configure vocabulary boosting if dictionary has terms or aliases
                let allTerms = mergedVocabularyTerms()
                if appState.dictionaryEnabled, !allTerms.isEmpty {
                    await configureVocabularyWithStatus(terms: allTerms)
                }
            }

            // Load emoji dictionary if enabled
            if appState.emojiExpansionEnabled {
                await textShortcutManager.loadEmojiDictionaryIfNeeded()
            }

            // Listen for dictionary/alias changes
            let reconfigureVocabulary: () -> Void = { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    let allTerms = self.mergedVocabularyTerms()
                    if self.appState.dictionaryEnabled, !allTerms.isEmpty {
                        await self.configureVocabularyWithStatus(terms: allTerms)
                    } else {
                        self.transcriptionEngine.disableVocabulary()
                        self.appState.vocabularyState = .idle
                    }
                }
            }
            personalDictionary.onTermsChanged = reconfigureVocabulary
            appState.onDictionaryEnabledChanged = reconfigureVocabulary
            textShortcutManager.onAliasesChanged = reconfigureVocabulary

            if #available(macOS 26, *), AIPostProcessor.isAvailable {
                aiPostProcessor = AIPostProcessor()
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

    // MARK: - Settings Window Lifecycle

    private func observeSettingsWindowClose() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title == "TeleTalk Settings" else { return }

        NSApp.setActivationPolicy(.accessory)
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
                if previousMic == .granted, appState.permissions.microphone == .denied {
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
            onStopRecording: { [weak self] in self?.stopPipeline() },
            onCancel: { [weak self] in self?.cancelPipeline() }
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
            try audioRecorder.startRecording(
                deviceUID: appState.selectedAudioDeviceUID,
                maxDuration: appState.maxRecordingDuration,
                minDuration: appState.minRecordingDuration
            )
            appState.recordingState = .listening
            if appState.audioFeedbackEnabled { SoundEffect.startRecording.play() }
            overlayWindow?.show()
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            showError("Mic error")
        }
    }

    private func stopPipeline() {
        appState.audioLevel = 0
        let samples = audioRecorder.stopRecording()

        guard let samples, !samples.isEmpty else {
            appState.recordingState = .idle
            overlayWindow?.hide()
            return
        }

        appState.recordingState = .transcribing
        if appState.audioFeedbackEnabled { SoundEffect.stopRecording.play() }

        let sampleCount = samples.count

        pipelineTask = Task { @MainActor in
            do {
                let text = try await transcriptionEngine.transcribe(samples: samples)

                guard !Task.isCancelled else { return }

                guard let text, !text.isEmpty else {
                    logger.info("Nothing transcribed")
                    showError("Nothing heard")
                    return
                }

                // AI enhancement (before alias/emoji expansion)
                var processedText = text
                if #available(macOS 26, *),
                   let hotkeyManager, hotkeyManager.lastTriggerWasAI,
                   appState.aiEnhancementEnabled,
                   let processor = aiPostProcessor as? AIPostProcessor
                {
                    appState.recordingState = .enhancing
                    processedText = await processor.enhance(
                        text: processedText,
                        systemPrompt: appState.aiSystemPrompt
                    )
                    guard !Task.isCancelled else { return }
                }

                // Post-process transcription
                if appState.aliasExpansionEnabled {
                    processedText = textShortcutManager.expandAliases(in: processedText)
                }
                if appState.emojiExpansionEnabled {
                    processedText = textShortcutManager.expandEmoji(in: processedText)
                }

                appState.recordingState = .inserting
                await textInserter.insert(text: processedText, method: appState.insertionMethod)

                let audioDuration = Double(sampleCount) / Constants.Audio.sampleRate
                let entry = TranscriptionEntry(
                    text: processedText,
                    audioDurationSeconds: audioDuration,
                    modelVersion: appState.selectedModelVersion
                )
                transcriptionHistory.add(entry)

                guard !Task.isCancelled else { return }

                // Brief "Done" display, then hide
                try? await Task.sleep(for: .milliseconds(
                    Int(Constants.UI.overlayFadeOutDuration * 1000)
                ))
                appState.recordingState = .idle
                overlayWindow?.hide()
            } catch {
                if Task.isCancelled { return }
                logger.error("Transcription failed: \(error.localizedDescription)")
                showError(error.localizedDescription)
            }
        }
    }

    private func cancelPipeline() {
        logger.info("Cancelling pipeline")
        pipelineTask?.cancel()
        pipelineTask = nil

        if appState.recordingState == .listening {
            _ = audioRecorder.stopRecording()
        }

        appState.recordingState = .idle
        appState.audioLevel = 0
        overlayWindow?.hide()
    }

    /// Merges PersonalDictionary terms with alias triggers so Parakeet recognizes alias words.
    private func mergedVocabularyTerms() -> [DictionaryTerm] {
        var terms = personalDictionary.terms
        if appState.aliasExpansionEnabled {
            for alias in textShortcutManager.aliases {
                terms.append(DictionaryTerm(text: alias.trigger))
            }
        }
        return terms
    }

    private func configureVocabularyWithStatus(terms: [DictionaryTerm]) async {
        appState.vocabularyState = .downloading
        do {
            try await transcriptionEngine.configureVocabulary(terms: terms)
            appState.vocabularyState = .ready
        } catch {
            logger.error("Vocabulary configuration failed: \(error.localizedDescription)")
            appState.vocabularyState = .error(error.localizedDescription)
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
