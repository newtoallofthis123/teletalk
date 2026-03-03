import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 400, height: 250)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("Settings will be configured here.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
