import SwiftUI
import VocabularyAI
import VocabularyCore

/// Settings → AI: the on-device model and the providers the learner can connect (SPEC C2).
struct AISettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var onDeviceAvailability = AppleOnDeviceClient().availability

    var body: some View {
        Form {
            Section {
                LabeledContent("In use") {
                    Text(verbatim: app.providerDisplayName)
                        .accessibilityIdentifier("ai-in-use")
                }
            }

            Section {
                Button {
                    app.settings.aiSelection = .onDevice
                } label: {
                    ProviderRow(
                        name: ProviderCatalog.onDevice.displayName,
                        status: onDeviceAvailability.statusText,
                        isSelected: app.settings.aiSelection.providerID == ProviderCatalog.onDevice.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("provider-\(ProviderCatalog.onDevice.id)")
            } header: {
                Text("On this device")
            } footer: {
                Text("Free and private. Nothing leaves your device. Best for short explanations.")
            }

            Section {
                ForEach(ProviderCatalog.all.filter { $0.kind != .appleOnDevice }) { provider in
                    NavigationLink {
                        ProviderDetailView(provider: provider)
                    } label: {
                        ProviderRow(
                            name: provider.displayName,
                            status: keyStatus(for: provider),
                            isSelected: app.settings.aiSelection.providerID == provider.id
                        )
                    }
                    .accessibilityIdentifier("provider-\(provider.id)")
                }
            } header: {
                Text("With your own key")
            } footer: {
                Text("Requests go straight from this device to the provider you choose, using your key. Keys stay in your Keychain and sync through iCloud Keychain.")
            }

            Section {
                Toggle("Send object photos", isOn: sharesPhotos)
                    .accessibilityIdentifier("ai-send-photos")
            } header: {
                Text("Photos")
            } footer: {
                Text("When you name a photographed object, a cloud provider gets a smaller copy of the photo, without its location, so it can see the object. When this is off, only what you call the object is sent. The on-device model never needs the photo.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Provider")
        .onAppear { onDeviceAvailability = AppleOnDeviceClient().availability }
    }

    private var sharesPhotos: Binding<Bool> {
        Binding {
            app.settings.sharesPhotosWithAI
        } set: {
            app.settings.sharesPhotosWithAI = $0
        }
    }

    private func keyStatus(for provider: ProviderDescriptor) -> LocalizedStringKey {
        if provider.id == ProviderCatalog.customID {
            return app.settings.customProviderBaseURL == nil ? "Not set up" : "Server set"
        }
        return app.router.hasAPIKey(for: provider.id) ? "Key saved" : "No key"
    }
}

private struct ProviderRow: View {
    let name: String
    let status: LocalizedStringKey
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension OnDeviceAvailability {
    var statusText: LocalizedStringKey {
        switch self {
        case .available: "Available"
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in Settings"
        case .deviceNotEligible: "Not supported on this device"
        case .modelNotReady: "The model is downloading"
        }
    }
}

#Preview {
    NavigationStack {
        AISettingsView().environment(AppModel.preview())
    }
}
