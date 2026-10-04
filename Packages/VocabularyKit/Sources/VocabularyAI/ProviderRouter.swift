import Foundation
import FoundationModels
import VocabularyCore

/// A ready-to-use client for the learner's selection.
public struct ProviderSetup: Sendable {
    public let provider: ProviderDescriptor
    public let modelID: String
    public let client: any GenerationClient
}

/// Turns the learner's provider selection into a working client (SPEC C2, ADR-003).
///
/// Keys are read from the secret store at the moment a client is built, so a key saved in Settings
/// is used by the very next request. The router never stores keys anywhere else.
public struct ProviderRouter: Sendable {
    private let secrets: any SecretStore
    private let customProviders: [CustomProvider]
    private let session: URLSession

    /// - Parameter customProviders: the providers the learner added (SPEC C2).
    public init(secrets: any SecretStore, customProviders: [CustomProvider] = [], session: URLSession? = nil) {
        self.secrets = secrets
        self.customProviders = customProviders
        // Provider requests keep nothing on disk and follow no redirect to another server.
        self.session = session ?? ProviderHTTP.session
    }

    /// A provider from the catalog or one the learner added.
    public func provider(id: String) -> ProviderDescriptor? {
        ProviderCatalog.provider(id: id) ?? customProviders.first { $0.id == id }.map(ProviderDescriptor.init(custom:))
    }

    /// The provider for a selection; selections that no longer exist fall back to on device.
    public func provider(for selection: AIProviderSelection) -> ProviderDescriptor {
        provider(id: selection.providerID) ?? ProviderCatalog.onDevice
    }

    /// The selected model, or the provider's first recommended model.
    public func modelID(for selection: AIProviderSelection) -> String {
        let provider = provider(for: selection)
        if provider.kind == .appleOnDevice { return "system" }
        if let model = selection.modelID?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            return model
        }
        return provider.recommendedModels.first?.id ?? ""
    }

    public func setup(for selection: AIProviderSelection) throws(AIError) -> ProviderSetup {
        let provider = provider(for: selection)
        let model = modelID(for: selection)
        switch provider.kind {
        case .appleOnDevice:
            return ProviderSetup(provider: provider, modelID: model, client: AppleOnDeviceClient())
        case .openAICompatible:
            guard let baseURL = provider.baseURL else { throw .missingEndpoint }
            guard !model.isEmpty else { throw .modelUnavailable }
            let key = try apiKey(for: provider)
            return ProviderSetup(
                provider: provider,
                modelID: model,
                client: OpenAICompatibleClient(provider: provider, baseURL: baseURL, model: model, apiKey: key, session: session)
            )
        case .anthropic:
            guard let baseURL = provider.baseURL else { throw .missingEndpoint }
            guard let key = try apiKey(for: provider) else { throw .missingAPIKey }
            return ProviderSetup(
                provider: provider,
                modelID: model,
                client: AnthropicClient(baseURL: baseURL, model: model, apiKey: key, session: session)
            )
        }
    }

    /// An insight service for the selection. If the provider can't be set up (no key, no server
    /// address), the service reports that error when it is used, so the capture UI can show it.
    public func insightService(for selection: AIProviderSelection) -> InsightService {
        let provider = provider(for: selection)
        let source = InsightSource(
            providerID: provider.id,
            modelID: provider.kind == .appleOnDevice ? nil : modelID(for: selection)
        )
        do {
            let setup = try setup(for: selection)
            return InsightService(client: setup.client, strategy: provider.insightStrategy, source: source)
        } catch {
            return InsightService(client: FailingClient(error: error), strategy: provider.insightStrategy, source: source)
        }
    }

    /// Models the provider offers for the saved key.
    public func availableModels(providerID: String) async throws(AIError) -> [String] {
        // Listing needs no model, but setting up a client does.
        let setup = try setup(for: AIProviderSelection(providerID: providerID, modelID: "list"))
        switch setup.client {
        case let client as OpenAICompatibleClient: return try await client.listModels()
        case let client as AnthropicClient: return try await client.listModels()
        default: return []
        }
    }

    /// Makes one tiny structured request, so a wrong key, model or endpoint shows up in Settings.
    public func testConnection(for selection: AIProviderSelection) async throws(AIError) {
        let setup = try setup(for: selection)
        let request = GenerationRequest(
            instructions: "You check that a connection works.",
            prompt: "Reply with the word OK in the reply field.",
            maximumResponseTokens: 40
        )
        _ = try await setup.client.generate(request, as: ConnectionCheck.self)
    }

    /// "OpenAI · gpt-6-luna", or just the on-device model's name.
    public func displayName(for selection: AIProviderSelection) -> String {
        let provider = provider(for: selection)
        guard provider.kind != .appleOnDevice else { return provider.displayName }
        return "\(provider.displayName) · \(modelID(for: selection))"
    }

    public func hasAPIKey(for providerID: String) -> Bool {
        ((try? secrets.secret(for: providerID)) ?? nil)?.isEmpty == false
    }

    private func apiKey(for provider: ProviderDescriptor) throws(AIError) -> String? {
        let key: String?
        do {
            key = try secrets.secret(for: provider.id)
        } catch {
            throw .unknown(error.localizedDescription)
        }
        if provider.requiresAPIKey && (key ?? "").isEmpty {
            throw .missingAPIKey
        }
        return key
    }
}

@Generable
struct ConnectionCheck {
    @Guide(description: "The word OK")
    var reply: String
}

/// Stands in for a provider that couldn't be set up; every request reports why.
struct FailingClient: GenerationClient {
    let error: AIError

    func generate(_ request: GenerationRequest, schema: GenerationSchema) async throws(AIError) -> GeneratedContent {
        throw error
    }
}
