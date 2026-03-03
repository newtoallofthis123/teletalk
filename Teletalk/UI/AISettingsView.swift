import KeyboardShortcuts
import SwiftUI

// MARK: - AI Tab

@available(macOS 26, *)
struct AISettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Toggle("Enable AI-enhanced dictation", isOn: $state.aiEnhancementEnabled)

                if appState.aiEnhancementEnabled {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .frame(width: 20)
                        Text("AI Dictation")
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: .dictateAI)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            } header: {
                Label("AI Enhancement", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            } footer: {
                Text(
                    "Uses Apple Intelligence to clean up transcriptions. Assign a hotkey to use AI-enhanced dictation."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            if appState.aiEnhancementEnabled {
                Section {
                    TextEditor(text: $state.aiSystemPrompt)
                        .frame(minHeight: 80)
                        .font(.system(.body, design: .monospaced))

                    Button("Reset to Default") {
                        appState.aiSystemPrompt = Constants.AI.defaultSystemPrompt
                    }
                } header: {
                    Label("System Prompt", systemImage: "text.quote")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Instructions for the AI model. Controls how transcriptions are cleaned up.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
