import SwiftUI

/// First-run setup flow: permissions → model download → ready.
struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var currentStep: SetupStep = .permissions

    enum SetupStep {
        case permissions
        case modelDownload
        case ready
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to TeleTalk")
                .font(.title.bold())

            switch currentStep {
            case .permissions:
                permissionsStep
            case .modelDownload:
                modelDownloadStep
            case .ready:
                readyStep
            }
        }
        .frame(width: 400, height: 300)
        .padding()
    }

    // MARK: - Steps

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Text("TeleTalk needs a few permissions to work.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    PermissionBadge(status: appState.permissions.microphone)
                    Text("Microphone")
                    Spacer()
                    if appState.permissions.microphone != .granted {
                        Button("Grant") {
                            Task {
                                appState.permissions.microphone = await Permissions.requestMicrophone()
                            }
                        }
                    }
                }

                HStack {
                    PermissionBadge(status: appState.permissions.accessibility)
                    Text("Accessibility")
                    Spacer()
                    if appState.permissions.accessibility != .granted {
                        Button("Grant") {
                            Permissions.requestAccessibility()
                            // Re-check after short delay
                            Task {
                                try? await Task.sleep(for: .seconds(1))
                                appState.permissions.accessibility = Permissions.accessibilityStatus()
                            }
                        }
                    }
                }
            }
            .padding()

            Button("Continue") {
                currentStep = .modelDownload
            }
            .disabled(appState.permissions.microphone != .granted)
        }
    }

    private var modelDownloadStep: some View {
        VStack(spacing: 16) {
            switch appState.modelState {
            case .notDownloaded:
                Text("The transcription model needs to be downloaded.")
                    .foregroundStyle(.secondary)
                Text("This is a one-time download.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                // Model loading is triggered by AppDelegate after permissions.
                // If we're here and model isn't downloading yet, show a waiting state.
                ProgressView()

            case let .downloading(progress):
                Text("Downloading model…")
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .frame(width: 200)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Model ready!")
                Button("Continue") {
                    currentStep = .ready
                }

            case let .error(msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(msg)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're all set!")
                .font(.title2)

            Text("Press **Ctrl+Shift+Space** to start dictating.")
                .foregroundStyle(.secondary)

            Button("Done") {
                UserDefaults.standard.set(true, forKey: Constants.Defaults.hasCompletedSetup)
                // Close the setup window
                NSApplication.shared.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
