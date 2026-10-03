import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        Label("Languages", systemImage: "globe")
                    }
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        Label("AI Provider", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("settings-ai")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView().environment(AppModel.preview())
}
