import Foundation
import Testing
import VocabularyCore
@testable import VocabularyAI

@Suite struct ProviderRouterTests {
    private let secrets = InMemorySecretStore()
    private var router: ProviderRouter { ProviderRouter(secrets: secrets) }

    @Test func theDefaultSelectionUsesTheOnDeviceModelStepwise() throws {
        let setup = try router.setup(for: .onDevice)
        #expect(setup.client is AppleOnDeviceClient)
        #expect(setup.provider.id == AIProviderSelection.onDevice.providerID)
        #expect(router.insightService(for: .onDevice).strategy == .stepwise)
    }

    @Test func cloudProvidersNeedAKey() {
        #expect(throws: AIError.missingAPIKey) {
            try router.setup(for: AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna"))
        }
    }

    @Test func buildsTheRightClientWithTheSavedKey() throws {
        try secrets.setSecret("sk-openai", for: "openai")
        try secrets.setSecret("sk-ant", for: "anthropic")

        let openAI = try router.setup(for: AIProviderSelection(providerID: "openai", modelID: "gpt-5.4-nano"))
        let openAIClient = try #require(openAI.client as? OpenAICompatibleClient)
        #expect(openAIClient.model == "gpt-5.4-nano")
        #expect(openAIClient.baseURL.absoluteString == "https://api.openai.com/v1")

        let claude = try router.setup(for: AIProviderSelection(providerID: "anthropic"))
        let claudeClient = try #require(claude.client as? AnthropicClient)
        #expect(claudeClient.model == "claude-haiku-4-5", "without a model the first recommended one is used")
        #expect(router.insightService(for: AIProviderSelection(providerID: "anthropic")).strategy == .singleCall)
    }

    @Test func aProviderTheLearnerAddedNeedsNoKey() throws {
        let ollama = CustomProvider(name: "Ollama", address: "http://localhost:11434/v1")
        let router = ProviderRouter(secrets: secrets, customProviders: [ollama])
        let selection = AIProviderSelection(providerID: ollama.id, modelID: "llama4")

        let setup = try router.setup(for: selection)
        let client = try #require(setup.client as? OpenAICompatibleClient)
        #expect(client.baseURL == URL(string: "http://localhost:11434/v1"))
        #expect(client.model == "llama4")
        #expect(setup.provider.displayName == "Ollama")
        #expect(router.displayName(for: selection) == "Ollama · llama4")
        #expect(router.insightService(for: selection).strategy == .singleCall)
    }

    @Test func aLearnerProviderNeedsAUsableAddressAndAModel() throws {
        let broken = CustomProvider(name: "Typo", address: "localhost:11434")
        #expect(throws: AIError.missingEndpoint) {
            try ProviderRouter(secrets: secrets, customProviders: [broken]).setup(for: AIProviderSelection(providerID: broken.id, modelID: "llama4"))
        }
        let ollama = CustomProvider(name: "Ollama", address: "http://localhost:11434/v1")
        #expect(throws: AIError.modelUnavailable) {
            try ProviderRouter(secrets: secrets, customProviders: [ollama]).setup(for: AIProviderSelection(providerID: ollama.id))
        }
    }

    @Test func aRemovedLearnerProviderFallsBackToTheOnDeviceModel() throws {
        let setup = try router.setup(for: AIProviderSelection(providerID: CustomProvider.idPrefix + "gone", modelID: "llama4"))
        #expect(setup.provider.id == AIProviderSelection.onDevice.providerID)
    }

    @Test func unknownProvidersFallBackToTheOnDeviceModel() throws {
        let setup = try router.setup(for: AIProviderSelection(providerID: "removed-provider"))
        #expect(setup.provider.id == AIProviderSelection.onDevice.providerID)
    }

    @Test func aMissingKeySurfacesWhenTheServiceIsUsed() async {
        let service = router.insightService(for: AIProviderSelection(providerID: "mistral"))
        await #expect(throws: AIError.missingAPIKey) {
            try await service.insight(for: InsightRequest(term: "pitch", sentence: nil, language: .english, nativeLanguage: .turkish))
        }
    }

    @Test func describesTheSelectionForDisplay() throws {
        #expect(router.displayName(for: AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna")) == "OpenAI · gpt-6-luna")
        #expect(router.displayName(for: .onDevice) == ProviderCatalog.onDevice.displayName)
    }
}
