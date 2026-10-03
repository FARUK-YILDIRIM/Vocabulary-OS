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
