import SwiftUI
import VocabularyAI
import VocabularyCore

/// Settings → AI: the on-device model, the providers we list and the ones the learner added
/// (SPEC C2).
struct AISettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var onDeviceAvailability = AppleOnDeviceClient().availability
    @State private var isAddingProvider = false

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
                        status: Text(onDeviceAvailability.statusText),
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
                            status: app.router.hasAPIKey(for: provider.id) ? Text("Key saved") : Text("No key"),
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
                ForEach(app.settings.customProviders) { custom in
                    NavigationLink {
                        ProviderDetailView(provider: ProviderDescriptor(custom: custom))
                    } label: {
                        ProviderRow(
                            name: custom.name,
                            status: Text(verbatim: custom.address),
                            isSelected: app.settings.aiSelection.providerID == custom.id
                        )
                    }
                    .accessibilityIdentifier("provider-\(custom.id)")
                }
                .onDelete(perform: deleteProviders)
                Button {
                    isAddingProvider = true
                } label: {
                    Label("Add a Provider", systemImage: "plus")
                }
                .accessibilityIdentifier("provider-add")
            } header: {
                Text("Your own providers")
            } footer: {
                Text("Any service with an OpenAI-compatible API: Ollama or LM Studio on your Mac, Azure OpenAI, Amazon Bedrock or your company's gateway.")
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
        .sheet(isPresented: $isAddingProvider) {
            NavigationStack {
                CustomProviderEditor()
            }
        }
    }

    private var sharesPhotos: Binding<Bool> {
        Binding {
            app.settings.sharesPhotosWithAI
        } set: {
            app.settings.sharesPhotosWithAI = $0
        }
    }

    private func deleteProviders(at offsets: IndexSet) {
        for custom in offsets.map({ app.settings.customProviders[$0] }) {
            app.deleteCustomProvider(custom)
        }
    }
}

private struct ProviderRow: View {
    let name: String
    let status: Text
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                status.font(.caption).foregroundStyle(.secondary)
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
