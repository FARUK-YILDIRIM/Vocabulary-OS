import SwiftUI
import VocabularyAI
import VocabularyCore

/// Connect one cloud provider: key, model, connection test, and switching to it (SPEC C2).
struct ProviderDetailView: View {
    @Environment(AppModel.self) private var app
    let provider: ProviderDescriptor

    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var serverDraft = ""
    @State private var model = ""
    @State private var customModel = ""
    @State private var fetchedModels: [String] = []
    @State private var isLoadingModels = false
    @State private var testState = TestState.idle
    @State private var isShowingPrivacyNotice = false
    @State private var errorMessage: String?

    private enum TestState: Equatable {
        case idle, running, succeeded
        case failed(String)
    }

    private var isCustom: Bool { provider.id == ProviderCatalog.customID }

    var body: some View {
        Form {
            if let url = provider.apiKeyPageURL {
                Section {
                    Link(destination: url) {
                        Label("Create an API key at \(provider.displayName)", systemImage: "key")
                    }
                } footer: {
                    Text("You pay the provider directly for what you use. Vocabulary-OS never sees your key or your words.")
                }
            }

            if isCustom {
                Section {
                    TextField(ProviderCatalog.suggestedCustomBaseURL.absoluteString, text: $serverDraft)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit(saveServer)
                        .accessibilityIdentifier("provider-server")
                    Button("Save Address", action: saveServer)
                } header: {
                    Text("Server address")
                } footer: {
                    Text("For example Ollama (port 11434) or LM Studio (port 1234) on your Mac or local network.")
                }
            }

            Section {
                if hasKey {
                    LabeledContent("API key") {
                        Text("Saved in Keychain").foregroundStyle(.secondary)
                    }
                    Button("Remove Key", role: .destructive, action: removeKey)
                } else {
                    SecureField(isCustom ? "Optional API key" : "Paste your API key", text: $keyDraft)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(saveKey)
                        .accessibilityIdentifier("provider-key")
                    Button("Save Key", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("provider-save-key")
                }
            } header: {
                Text("API key")
            }

            Section {
                Picker("Model", selection: $model) {
                    ForEach(modelChoices, id: \.self) { id in
                        Text(verbatim: id).tag(id)
                    }
                }
                .accessibilityIdentifier("provider-model")
                TextField("Other model ID", text: $customModel)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if provider.supportsModelListing {
                    Button {
                        Task { await loadModels() }
                    } label: {
                        HStack {
                            Text("Load Models from \(provider.displayName)")
                            if isLoadingModels { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isLoadingModels || (!hasKey && provider.requiresAPIKey))
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Recommended models are cheap and fast. Model names change; loading the list shows what your key can use.")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        switch testState {
                        case .idle: EmptyView()
                        case .running: ProgressView()
                        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                        }
                    }
                }
                .disabled(testState == .running || !canUse)
                .accessibilityIdentifier("provider-test")
                if case .failed(let message) = testState {
                    Text(verbatim: message).font(.callout).foregroundStyle(.red)
                }

                Button {
                    use()
                } label: {
                    Text(isSelected ? "In Use" : "Use This Provider").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSelected || !canUse)
                .accessibilityIdentifier("provider-use")
            }

            if let errorMessage {
                Section {
                    Text(verbatim: errorMessage).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(provider.displayName)
        .onAppear(perform: load)
        .alert("Before you use \(provider.displayName)", isPresented: $isShowingPrivacyNotice) {
            Button("Continue") {
                app.settings.hasAcknowledgedCloudPrivacy = true
                select()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To explain a word, Vocabulary-OS sends the word, its sentence and your language names to \(provider.displayName) with your API key. Quizzes and podcasts send the words you choose and their meanings. Requests go directly from this device; there is no Vocabulary-OS server.")
        }
    }

    // MARK: State

    private var selectedModel: String {
        let custom = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? model : custom
    }

    private var modelChoices: [String] {
        var choices = provider.recommendedModels.map(\.id)
        for id in fetchedModels where !choices.contains(id) {
            choices.append(id)
        }
        if !model.isEmpty, !choices.contains(model) {
            choices.insert(model, at: 0)
        }
        return choices
    }

    private var isSelected: Bool {
        app.settings.aiSelection == AIProviderSelection(providerID: provider.id, modelID: selectedModel)
    }

    private var canUse: Bool {
        guard !selectedModel.isEmpty else { return false }
        if isCustom { return app.settings.customProviderBaseURL != nil }
        return hasKey
    }

    private var selection: AIProviderSelection {
        AIProviderSelection(providerID: provider.id, modelID: selectedModel)
    }

    private func load() {
        hasKey = app.router.hasAPIKey(for: provider.id)
        serverDraft = app.settings.customProviderBaseURL ?? ""
        if app.settings.aiSelection.providerID == provider.id, let current = app.settings.aiSelection.modelID {
            model = current
        } else {
            model = provider.recommendedModels.first?.id ?? ""
        }
    }

    // MARK: Actions

    private func saveKey() {
        do {
            try app.secrets.setSecret(keyDraft, for: provider.id)
            keyDraft = ""
            hasKey = app.router.hasAPIKey(for: provider.id)
            errorMessage = nil
            testState = .idle
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeKey() {
        try? app.secrets.setSecret(nil, for: provider.id)
        hasKey = false
        testState = .idle
        if app.settings.aiSelection.providerID == provider.id && provider.requiresAPIKey {
            app.settings.aiSelection = .onDevice
        }
    }

    private func saveServer() {
        let trimmed = serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            app.settings.customProviderBaseURL = nil
            return
        }
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https", url.host() != nil else {
            errorMessage = String(localized: "Enter a full address such as http://localhost:11434/v1.")
            return
        }
        errorMessage = nil
        app.settings.customProviderBaseURL = url.absoluteString
    }

    private func loadModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do throws(AIError) {
            fetchedModels = try await app.router.availableModels(providerID: provider.id, customBaseURL: app.customBaseURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func testConnection() async {
        testState = .running
        do throws(AIError) {
            try await app.router.testConnection(for: selection, customBaseURL: app.customBaseURL)
            testState = .succeeded
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }

    private func use() {
        if app.settings.hasAcknowledgedCloudPrivacy {
            select()
        } else {
            isShowingPrivacyNotice = true
        }
    }

    private func select() {
        app.settings.aiSelection = selection
    }
}
