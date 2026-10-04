import SwiftUI
import VocabularyAI
import VocabularyCore

/// Connect one cloud provider: key, model, connection test, and switching to it (SPEC C2). For a
/// provider the learner added, also its name and address, and deleting it.
struct ProviderDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let provider: ProviderDescriptor

    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var nameDraft = ""
    @State private var serverDraft = ""
    @State private var keyWasRemoved = false
    @State private var isConfirmingDelete = false
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

    /// The provider as the learner added it, if they did; kept current while it is edited here.
    private var custom: CustomProvider? {
        app.settings.customProviders.first { $0.id == provider.id }
    }

    private var isCustom: Bool { CustomProvider.isCustom(provider.id) }

    private var name: String { custom?.name ?? provider.displayName }

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
                    TextField("Name", text: $nameDraft)
                        .accessibilityIdentifier("provider-name")
                    TextField("Address", text: $serverDraft, prompt: Text(verbatim: ProviderCatalog.exampleCustomAddress))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit(saveServer)
                        .accessibilityIdentifier("provider-server")
                    Button("Save Changes", action: saveServer)
                        .disabled(nameDraft == custom?.name && serverDraft == custom?.address)
                } header: {
                    Text("Server")
                } footer: {
                    if keyWasRemoved {
                        Text("The provider now points to another server, so its key was removed. Enter the key for the new server.")
                    } else {
                        Text("A key only ever goes to the server it was entered for: moving the provider to another server removes it.")
                    }
                }
            }

            Section {
                if hasKey {
                    LabeledContent("API key") {
                        Text("Saved in Keychain").foregroundStyle(.secondary)
                    }
                    Button("Remove Key", role: .destructive, action: removeKey)
                } else {
                    SecureField(isCustom ? "API key (optional)" : "Paste your API key", text: $keyDraft)
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
                    .accessibilityIdentifier("provider-other-model")
                if provider.supportsModelListing {
                    Button {
                        Task { await loadModels() }
                    } label: {
                        HStack {
                            Text("Load Models from \(name)")
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
                        .accessibilityIdentifier("provider-error")
                }
            }

            if isCustom {
                Section {
                    Button("Delete Provider", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .accessibilityIdentifier("provider-delete")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(name)
        .onAppear(perform: load)
        .confirmationDialog("Delete \(name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Provider", role: .destructive) {
                if let custom {
                    app.deleteCustomProvider(custom)
                }
                dismiss()
            }
        } message: {
            Text("Its key is removed from your Keychain. Your words stay as they are.")
        }
        .alert("Before you use \(name)", isPresented: $isShowingPrivacyNotice) {
            Button("Continue") {
                app.settings.hasAcknowledgedCloudPrivacy = true
                select()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To explain a word, Vocabulary-OS sends the word, its sentence and your language names to \(name) with your API key. Quizzes and podcasts send the words you choose and their meanings, and object photos are sent only if you turn that on. Requests go directly from this device; there is no Vocabulary-OS server.")
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
        if isCustom { return custom?.url != nil }
        return hasKey
    }

    private var selection: AIProviderSelection {
        AIProviderSelection(providerID: provider.id, modelID: selectedModel)
    }

    private func load() {
        hasKey = app.router.hasAPIKey(for: provider.id)
        nameDraft = custom?.name ?? ""
        serverDraft = custom?.address ?? ""
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
        guard var updated = custom else { return }
        switch ServerAddress.validate(serverDraft) {
        case .failure(let problem):
            errorMessage = problem.message
        case .success(let url):
            let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                updated.name = name
            }
            updated.address = url.absoluteString
            keyWasRemoved = app.updateCustomProvider(updated)
            hasKey = app.router.hasAPIKey(for: provider.id)
            nameDraft = updated.name
            serverDraft = updated.address
            errorMessage = nil
            testState = .idle
        }
    }

    private func loadModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do throws(AIError) {
            fetchedModels = try await app.router.availableModels(providerID: provider.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func testConnection() async {
        testState = .running
        do throws(AIError) {
            try await app.router.testConnection(for: selection)
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
