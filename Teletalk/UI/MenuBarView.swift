import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }

        Divider()

        SettingsLink {
            Text("Settings...")
        }

        Divider()

        Button("Quit TeleTalk") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
