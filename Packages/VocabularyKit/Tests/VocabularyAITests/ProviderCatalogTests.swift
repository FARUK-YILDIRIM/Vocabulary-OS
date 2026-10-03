import Foundation
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite struct ProviderCatalogTests {
    @Test func theOnDeviceModelComesFirstAndMatchesTheDefaultSelection() {
        #expect(ProviderCatalog.all.first?.id == AIProviderSelection.onDevice.providerID)
        #expect(ProviderCatalog.onDevice.kind == .appleOnDevice)
        #expect(!ProviderCatalog.onDevice.requiresAPIKey)
    }

    @Test func identifiersAreUnique() {
        let ids = ProviderCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for provider in ProviderCatalog.all {
            let models = provider.recommendedModels.map(\.id)
            #expect(Set(models).count == models.count, "\(provider.id) repeats a model")
        }
    }

    @Test func cloudProvidersUseHTTPSAndLinkToTheirKeyPage() throws {
        for provider in ProviderCatalog.all where provider.kind != .appleOnDevice && provider.id != ProviderCatalog.customID {
            let baseURL = try #require(provider.baseURL, "\(provider.id) has no base URL")
            #expect(baseURL.scheme == "https", "\(provider.id)")
            #expect(provider.apiKeyPageURL?.scheme == "https", "\(provider.id)")
            #expect(provider.requiresAPIKey, "\(provider.id)")
            #expect(!provider.recommendedModels.isEmpty, "\(provider.id)")
        }
    }

    @Test func theCustomEndpointIsConfiguredByTheLearner() {
        let custom = ProviderCatalog.custom
        #expect(custom.kind == .openAICompatible)
        #expect(custom.baseURL == nil)
        #expect(!custom.requiresAPIKey)
        #expect(ProviderCatalog.suggestedCustomBaseURL.absoluteString == "http://localhost:11434/v1")
    }

    @Test func providerQuirksFollowTheirAPIs() throws {
        // Verified against each provider's documentation on 2026-10-04 (ADR-003).
        #expect(try #require(ProviderCatalog.provider(id: "openai")).tokenLimitField == .maxCompletionTokens)
        #expect(try #require(ProviderCatalog.provider(id: "deepseek")).structuredOutput == .jsonObject)
        #expect(try #require(ProviderCatalog.provider(id: "anthropic")).kind == .anthropic)
        #expect(try #require(ProviderCatalog.provider(id: "openrouter")).quirks.contains(.openRouterRequireParameters))
        #expect(ProviderCatalog.provider(id: "nope") == nil)
    }
}

@Suite struct InMemorySecretStoreTests {
    @Test func storesReplacesAndDeletesSecrets() throws {
        let store = InMemorySecretStore()
        #expect(try store.secret(for: "openai") == nil)
        try store.setSecret("sk-one", for: "openai")
        try store.setSecret("sk-two", for: "openai")
        #expect(try store.secret(for: "openai") == "sk-two")
        try store.setSecret(nil, for: "openai")
        #expect(try store.secret(for: "openai") == nil)
    }

    @Test func blankSecretsAreTreatedAsDeletion() throws {
        let store = InMemorySecretStore()
        try store.setSecret("sk-one", for: "openai")
        try store.setSecret("   ", for: "openai")
        #expect(try store.secret(for: "openai") == nil)
    }
}

/// Uses the real Keychain of this Mac. Opt in with `VOS_KEYCHAIN_TESTS=1`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VOS_KEYCHAIN_TESTS"] == "1"))
struct KeychainSecretStoreTests {
    @Test func roundTripsAKeyAndCleansUp() throws {
        let store = KeychainSecretStore(service: "app.vocabularyos.tests", accessGroup: nil, synchronizes: false)
        let account = "test-\(UUID().uuidString)"
        defer { try? store.setSecret(nil, for: account) }

        try store.setSecret("sk-test-123", for: account)
        #expect(try store.secret(for: account) == "sk-test-123")
        try store.setSecret("sk-test-456", for: account)
        #expect(try store.secret(for: account) == "sk-test-456")
        try store.setSecret(nil, for: account)
        #expect(try store.secret(for: account) == nil)
    }
}
