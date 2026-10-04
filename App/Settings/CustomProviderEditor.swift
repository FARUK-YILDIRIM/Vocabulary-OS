import SwiftUI
import VocabularyAI
import VocabularyCore

/// Adds a provider the learner runs or subscribes to: a name, its address and an optional key
/// (SPEC C2). The model is chosen afterwards, on the provider's page.
struct CustomProviderEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var key = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text(verbatim: "Ollama"))
                    .accessibilityIdentifier("custom-name")
                TextField("Address", text: $address, prompt: Text(verbatim: ProviderCatalog.exampleCustomAddress))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .accessibilityIdentifier("custom-address")
                SecureField("API key (optional)", text: $key)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("custom-key")
            } footer: {
                if let errorMessage {
                    Text(verbatim: errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("custom-error")
                } else {
                    Text("The address is the part before /chat/completions: for example http://localhost:11434/v1 for Ollama on this Mac, or https://YOUR-RESOURCE.openai.azure.com/openai/v1 for Azure OpenAI.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Add a Provider")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: add)
                    .disabled(name.trimmed.isEmpty || address.trimmed.isEmpty)
                    .accessibilityIdentifier("custom-add")
            }
        }
    }

    private func add() {
        switch ServerAddress.validate(address) {
        case .failure(let problem):
            errorMessage = problem.message
        case .success(let url):
            let provider = CustomProvider(name: name.trimmed, address: url.absoluteString)
            if !key.trimmed.isEmpty {
                do {
                    try app.secrets.setSecret(key.trimmed, for: provider.id)
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
            }
            app.settings.customProviders.append(provider)
            dismiss()
        }
    }
}

extension ServerAddress.Problem {
    /// What to tell the learner about an address the app can't use.
    var message: String {
        switch self {
        case .notAnAddress:
            String(localized: "Enter a full address that starts with https:// or http://.")
        case .plainHTTPOnInternet:
            String(localized: "Use https:// for a server on the internet, so your key and words travel encrypted. Plain http:// works only for this device and your local network.")
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
