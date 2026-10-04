import Foundation
import Testing
import VocabularyCore
@testable import VocabularyData

@MainActor
@Suite struct SettingsStoreTests {
    @Test func startsWithDefaultsOnAFreshInstall() {
        let store = SettingsStore(backing: InMemoryKeyValueBacking())
        #expect(store.profile == nil)
        #expect(!store.isOnboarded)
        #expect(store.aiSelection == .onDevice)
        #expect(store.reviewLimits == ReviewLimits())
    }

    @Test func persistsTheProfileAcrossInstances() throws {
        let backing = InMemoryKeyValueBacking()
        let profile = try LearnerProfile(native: .turkish, learning: [.english, .german])
        SettingsStore(backing: backing).profile = profile

        let reopened = SettingsStore(backing: backing)
        #expect(reopened.profile == profile)
        #expect(reopened.isOnboarded)
    }

    @Test func persistsAISelectionAndReviewLimits() {
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        store.aiSelection = AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna")
        store.reviewLimits = ReviewLimits(newPerDay: 5, reviewsPerDay: 60)

        let reopened = SettingsStore(backing: backing)
        #expect(reopened.aiSelection == AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna"))
        #expect(reopened.reviewLimits == ReviewLimits(newPerDay: 5, reviewsPerDay: 60))
    }

    @Test func reviewLimitsAreClampedToSaneRanges() {
        #expect(ReviewLimits(newPerDay: -3, reviewsPerDay: 0) == ReviewLimits(newPerDay: 0, reviewsPerDay: 1))
        #expect(ReviewLimits(newPerDay: 10_000, reviewsPerDay: 10_000) == ReviewLimits(newPerDay: 200, reviewsPerDay: 2_000))
    }

    @Test func appliesChangesMadeOnAnotherDevice() throws {
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        let profile = try LearnerProfile(native: .english, learning: [.spanish])

        backing.simulateExternalChange(key: SettingsStore.Key.profile, value: try JSONEncoder().encode(profile))

        #expect(store.profile == profile)
    }

    @Test func aChangeThisVersionCantReadKeepsTheCurrentSettings() throws {
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        let profile = try LearnerProfile(native: .turkish, learning: [.english])
        store.profile = profile
        store.reviewLimits = ReviewLimits(newPerDay: 5, reviewsPerDay: 60)

        backing.simulateExternalChange(key: SettingsStore.Key.profile, value: Data(#"{"native":"ka","learning":["en"]}"#.utf8))
        backing.simulateExternalChange(key: SettingsStore.Key.reviewLimits, value: Data("not json".utf8))
        #expect(store.profile == profile, "the learner isn't sent back to onboarding")
        #expect(store.reviewLimits == ReviewLimits(newPerDay: 5, reviewsPerDay: 60))

        backing.simulateExternalChange(key: SettingsStore.Key.profile, value: nil)
        #expect(store.profile == nil, "a profile removed on another device is removed")
    }

    @Test func ignoresCorruptValues() {
        let backing = InMemoryKeyValueBacking()
        backing.setData(Data("not json".utf8), forKey: SettingsStore.Key.profile)
        backing.setData(Data(#"{"native":"tr","learning":["tr"]}"#.utf8), forKey: SettingsStore.Key.aiSelection)

        let store = SettingsStore(backing: backing)
        #expect(store.profile == nil)
        #expect(store.aiSelection == .onDevice)
    }

    @Test func clearingTheProfileRemovesIt() throws {
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        store.profile = try LearnerProfile(native: .turkish, learning: [.english])
        store.profile = nil
        #expect(SettingsStore(backing: backing).profile == nil)
    }
}

@MainActor
@Suite struct UbiquitousKeyValueBackingTests {
    private func makeDefaults() -> UserDefaults {
        let name = "vos-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func writesToBothCloudAndLocalMirror() {
        let cloud = FakeCloudStore()
        let defaults = makeDefaults()
        let backing = UbiquitousKeyValueBacking(cloud: cloud, mirror: defaults)

        backing.setData(Data("v1".utf8), forKey: "k")

        #expect(cloud.values["k"] == Data("v1".utf8))
        #expect(defaults.data(forKey: "vos.k") == Data("v1".utf8))
    }

    @Test func fallsBackToTheMirrorWhenCloudIsEmpty() {
        // Unsigned builds have no key-value store entitlement, so only the mirror holds data.
        let defaults = makeDefaults()
        defaults.set(Data("local".utf8), forKey: "vos.k")
        let backing = UbiquitousKeyValueBacking(cloud: FakeCloudStore(), mirror: defaults)

        #expect(backing.data(forKey: "k") == Data("local".utf8))
    }

    @Test func readingCopiesCloudValuesIntoTheMirror() {
        // The Share extension reads only the mirror, so it must not lag behind iCloud.
        let cloud = FakeCloudStore()
        cloud.values["k"] = Data("remote".utf8)
        let defaults = makeDefaults()
        defaults.set(Data("stale".utf8), forKey: "vos.k")
        let backing = UbiquitousKeyValueBacking(cloud: cloud, mirror: defaults)

        #expect(backing.data(forKey: "k") == Data("remote".utf8))
        #expect(defaults.data(forKey: "vos.k") == Data("remote".utf8))
    }

    @Test func worksWithoutTheCloudStore() {
        let defaults = makeDefaults()
        let backing = UbiquitousKeyValueBacking(cloud: nil, mirror: defaults)
        backing.setData(Data("v".utf8), forKey: "k")
        #expect(backing.data(forKey: "k") == Data("v".utf8))
        backing.setData(nil, forKey: "k")
        #expect(backing.data(forKey: "k") == nil)
    }

    @Test func externalChangesRefreshTheMirrorAndNotify() async {
        let cloud = FakeCloudStore()
        let defaults = makeDefaults()
        let backing = UbiquitousKeyValueBacking(cloud: cloud, mirror: defaults)
        var changed: [String] = []
        backing.onExternalChange = { changed = $0 }

        cloud.values["k"] = Data("remote".utf8)
        backing.handleExternalChange(changedKeys: ["k"])

        #expect(changed == ["k"])
        #expect(defaults.data(forKey: "vos.k") == Data("remote".utf8))
    }
}

/// Stands in for NSUbiquitousKeyValueStore, which can't be instantiated in tests.
private final class FakeCloudStore: CloudKeyValueStoring {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
    func removeObject(forKey key: String) { values[key] = nil }
    @discardableResult func synchronize() -> Bool { true }
}

@MainActor
@Suite struct ProviderSettingsTests {
    @Test func persistsTheLearnersProvidersAndPrivacyAcknowledgement() {
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        #expect(store.customProviders.isEmpty)
        #expect(!store.hasAcknowledgedCloudPrivacy)

        let studio = CustomProvider(name: "LM Studio", address: "http://mac-mini.local:1234/v1")
        store.customProviders = [studio]
        store.hasAcknowledgedCloudPrivacy = true

        let reopened = SettingsStore(backing: backing)
        #expect(reopened.customProviders == [studio])
        #expect(reopened.hasAcknowledgedCloudPrivacy)
    }

    @Test func providersAddedOnAnotherDeviceAppear() throws {
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        let gateway = CustomProvider(name: "Gateway", address: "https://ai.example.com/v1")
        backing.simulateExternalChange(key: SettingsStore.Key.customProviders, value: try JSONEncoder().encode([gateway]))
        #expect(store.customProviders == [gateway])
    }

    @Test func aProviderOnThisDeviceIsChosenForThisDeviceOnly() throws {
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        let openAI = AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna")
        store.aiSelection = openAI
        let ollama = CustomProvider(name: "Ollama", address: "http://localhost:11434/v1")
        store.customProviders = [ollama]

        let local = AIProviderSelection(providerID: ollama.id, modelID: "llama4")
        store.aiSelection = local
        #expect(store.aiSelection == local)
        let shared = try #require(backing.data(forKey: SettingsStore.Key.aiSelection))
        #expect(try JSONDecoder().decode(AIProviderSelection.self, from: shared) == openAI, "the other devices keep their choice")

        // Another device switches to Claude; this one stays with its own server.
        let claude = AIProviderSelection(providerID: "anthropic")
        backing.simulateExternalChange(key: SettingsStore.Key.aiSelection, value: try JSONEncoder().encode(claude))
        #expect(store.aiSelection == local)

        // A provider every device can reach is shared again.
        store.aiSelection = openAI
        #expect(store.aiSelection == openAI)
        #expect(backing.deviceData(forKey: SettingsStore.Key.deviceAISelection) == nil)

        store.aiSelection = local
        #expect(SettingsStore(backing: backing).aiSelection == local, "this device's choice survives a relaunch")
    }

    @Test func removingAProviderForgetsTheChoiceOfIt() {
        let store = SettingsStore(backing: InMemoryKeyValueBacking())
        let ollama = CustomProvider(name: "Ollama", address: "http://localhost:11434/v1")
        let gateway = CustomProvider(name: "Gateway", address: "https://ai.example.com/v1")
        store.customProviders = [ollama, gateway]
        store.aiSelection = AIProviderSelection(providerID: "openai")
        store.aiSelection = AIProviderSelection(providerID: ollama.id, modelID: "llama4")

        store.removeCustomProvider(id: ollama.id)
        #expect(store.aiSelection == AIProviderSelection(providerID: "openai"), "back to the choice the devices share")
        store.aiSelection = AIProviderSelection(providerID: gateway.id, modelID: "gpt-6-luna")
        store.removeCustomProvider(id: gateway.id)
        #expect(store.aiSelection == .onDevice)
        #expect(store.customProviders.isEmpty)
    }

    @Test func sendingPhotosToTheAIIsOffUntilTheLearnerTurnsItOn() throws {
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        #expect(!store.sharesPhotosWithAI)

        backing.simulateExternalChange(key: SettingsStore.Key.sharesPhotosWithAI, value: try JSONEncoder().encode(true))
        #expect(store.sharesPhotosWithAI, "the choice follows the learner to their other devices")

        store.sharesPhotosWithAI = false
        #expect(!SettingsStore(backing: backing).sharesPhotosWithAI)
    }

    @Test func neverStoresAnAPIKey() throws {
        // Whatever the learner does in settings, nothing key-like reaches the unencrypted store.
        let backing = InMemoryKeyValueBacking()
        let store = SettingsStore(backing: backing)
        store.aiSelection = AIProviderSelection(providerID: "openai", modelID: "gpt-6-luna")
        store.customProviders = [CustomProvider(name: "LM Studio", address: "http://localhost:1234/v1")]
        for key in [SettingsStore.Key.profile, SettingsStore.Key.aiSelection, SettingsStore.Key.reviewLimits, SettingsStore.Key.customProviders] {
            let text = backing.data(forKey: key).map { String(decoding: $0, as: UTF8.self) } ?? ""
            #expect(!text.localizedCaseInsensitiveContains("sk-"))
            #expect(!text.localizedCaseInsensitiveContains("apiKey"))
        }
    }
}
