import Foundation
import Testing
import VocabularyAI
import VocabularyCore
import VocabularyData

/// API keys live only in the Keychain (SPEC C2, success criterion 12). This drives the settings the
/// way the AI settings screen does, with a distinctive key, and searches everything the settings
/// store wrote: the synced values, their local mirror and the values kept on the device.
@MainActor
@Suite struct KeyPrivacyTests {
    @Test func aSavedKeyAppearsNowhereInTheSettings() throws {
        let key = "sk-test-\(UUID().uuidString)"
        let suite = "vos-key-privacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(backing: UbiquitousKeyValueBacking(cloud: nil, mirror: defaults))
        let secrets = InMemorySecretStore()

        // A listed provider, as on its page in Settings.
        try secrets.setSecret(key, for: "openai")
        settings.hasAcknowledgedCloudPrivacy = true
        settings.aiSelection = AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna")
        // A provider of the learner's own, at this device's address, which is chosen on the device.
        let ollama = CustomProvider(name: "Ollama", address: "http://localhost:11434/v1")
        settings.customProviders = [ollama]
        try secrets.setSecret(key, for: ollama.id)
        settings.aiSelection = AIProviderSelection(providerID: ollama.id, modelID: "llama4")
        settings.sharesPhotosWithAI = true

        #expect(try secrets.secret(for: "openai") == key, "the key itself was saved")
        let written = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(!written.isEmpty, "the settings were written to the mirror")
        for (name, value) in written {
            let text = (value as? Data).map { String(decoding: $0, as: UTF8.self) } ?? "\(value)"
            #expect(!text.contains(key), "\(name) holds the key")
            #expect(!text.contains("sk-test"), "\(name) holds part of the key")
        }
    }
}
