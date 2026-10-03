import Foundation
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite struct ProviderRouterTests {
    private let secrets = InMemorySecretStore()
    private var router: ProviderRouter { ProviderRouter(secrets: secrets) }

    @Test func theDefaultSelectionUsesTheOnDeviceModelStepwise() throws {
        let setup = try router.setup(for: .onDevice, customBaseURL: nil)
        #expect(setup.client is AppleOnDeviceClient)
        #expect(setup.provider.id == AIProviderSelection.onDevice.providerID)
        #expect(router.insightService(for: .onDevice, customBaseURL: nil).strategy == .stepwise)
    }

    @Test func cloudProvidersNeedAKey() {
        #expect(throws: AIError.missingAPIKey) {
            try router.setup(for: AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna"), customBaseURL: nil)
        }
    }

    @Test func buildsTheRightClientWithTheSavedKey() throws {
        try secrets.setSecret("sk-openai", for: "openai")
        try secrets.setSecret("sk-ant", for: "anthropic")

        let openAI = try router.setup(for: AIProviderSelection(providerID: "openai", modelID: "gpt-5.4-nano"), customBaseURL: nil)
        let openAIClient = try #require(openAI.client as? OpenAICompatibleClient)
        #expect(openAIClient.model == "gpt-5.4-nano")
        #expect(openAIClient.baseURL.absoluteString == "https://api.openai.com/v1")

        let claude = try router.setup(for: AIProviderSelection(providerID: "anthropic"), customBaseURL: nil)
        let claudeClient = try #require(claude.client as? AnthropicClient)
        #expect(claudeClient.model == "claude-haiku-4-5", "without a model the first recommended one is used")
        #expect(router.insightService(for: AIProviderSelection(providerID: "anthropic"), customBaseURL: nil).strategy == .singleCall)
    }

    @Test func theCustomEndpointNeedsABaseURLButNoKey() throws {
        let selection = AIProviderSelection(providerID: "custom", modelID: "llama3.2")
        #expect(throws: AIError.self) {
            try router.setup(for: selection, customBaseURL: nil)
        }
        let local = try #require(URL(string: "http://localhost:11434/v1"))
        let client = try #require(try router.setup(for: selection, customBaseURL: local).client as? OpenAICompatibleClient)
        #expect(client.baseURL == local)
    }

    @Test func unknownProvidersFallBackToTheOnDeviceModel() throws {
        let setup = try router.setup(for: AIProviderSelection(providerID: "removed-provider"), customBaseURL: nil)
        #expect(setup.provider.id == AIProviderSelection.onDevice.providerID)
    }

    @Test func aMissingKeySurfacesWhenTheServiceIsUsed() async {
        let service = router.insightService(for: AIProviderSelection(providerID: "mistral"), customBaseURL: nil)
        await #expect(throws: AIError.missingAPIKey) {
            try await service.insight(for: InsightRequest(term: "pitch", sentence: nil, language: .english, nativeLanguage: .turkish))
        }
    }

    @Test func describesTheSelectionForDisplay() throws {
        #expect(router.displayName(for: AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna")) == "OpenAI · gpt-6-luna")
        #expect(router.displayName(for: .onDevice) == ProviderCatalog.onDevice.displayName)
    }
}
