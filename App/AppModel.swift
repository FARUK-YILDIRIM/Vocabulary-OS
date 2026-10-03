import Foundation
import Observation
import os
import SwiftData
import VocabularyAI
import VocabularyCore
import VocabularyData

/// Owns the app's long-lived dependencies and hands them to views through the environment.
@Observable
final class AppModel {
    let settings: SettingsStore
    let container: ModelContainer
    let repository: WordRepository
    @ObservationIgnored private let options: LaunchOptions

    init(settings: SettingsStore, container: ModelContainer, options: LaunchOptions = LaunchOptions()) {
        self.settings = settings
        self.container = container
        self.repository = WordRepository(container: container)
        self.options = options
    }

    /// Production wiring. UI tests launch with `-ui-testing YES` to start from a clean, in-memory
    /// state, optionally already onboarded with `-vos-preset-profile tr:en,de`.
    static func live(options: LaunchOptions = LaunchOptions()) -> AppModel {
        if options.isUITesting {
            let settings = SettingsStore(backing: InMemoryKeyValueBacking())
            settings.profile = options.presetProfile
            return AppModel(settings: settings, container: makeContainer(inMemory: true), options: options)
        }
        return AppModel(settings: SettingsStore(backing: makeSettingsBacking()), container: makeContainer(inMemory: false), options: options)
    }

    /// For SwiftUI previews: in-memory settings and store, optionally already onboarded.
    static func preview(profile: LearnerProfile? = try? LearnerProfile(native: .turkish, learning: [.english, .german])) -> AppModel {
        let settings = SettingsStore(backing: InMemoryKeyValueBacking())
        settings.profile = profile
        return AppModel(settings: settings, container: makeContainer(inMemory: true))
    }

    // MARK: AI

    /// The insight service for the learner's current provider. Only the on-device model exists until
    /// cloud providers arrive (task T16).
    func makeInsightService() -> InsightService {
        #if DEBUG
        if options.usesAIStub {
            return InsightService(client: StubGenerationClient(), strategy: .stepwise, source: InsightSource(providerID: "stub"))
        }
        #endif
        return InsightService(
            client: AppleOnDeviceClient(),
            strategy: .stepwise,
            source: InsightSource(providerID: AIProviderSelection.onDevice.providerID)
        )
    }

    var providerDisplayName: String {
        String(localized: "Apple on-device model")
    }

    // MARK: Wiring

    private static var isCloudSyncBuild: Bool {
        #if VOS_CLOUD_SYNC
        true
        #else
        false
        #endif
    }

    /// Builds with a Team ID get the iCloud key-value store entitlement and the `VOS_CLOUD_SYNC`
    /// condition (Config/Signing.local.xcconfig). Without the entitlement, touching the store logs a
    /// fault, so unsigned builds keep settings in UserDefaults only.
    private static func makeSettingsBacking() -> UbiquitousKeyValueBacking {
        #if VOS_CLOUD_SYNC
        UbiquitousKeyValueBacking(cloud: NSUbiquitousKeyValueStore.default)
        #else
        UbiquitousKeyValueBacking(cloud: nil)
        #endif
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        do {
            return try VocabularyStore.makeContainer(inMemory: inMemory, cloudSync: isCloudSyncBuild && !inMemory)
        } catch {
            // A store that can't open (for example after a failed migration) must not take the app down;
            // the learner can still capture into memory and the error is logged for diagnosis.
            Logger(subsystem: VocabularyCore.logSubsystem, category: "app")
                .fault("Could not open the word store: \(error.localizedDescription, privacy: .public)")
            guard let fallback = try? VocabularyStore.makeContainer(inMemory: true, cloudSync: false) else {
                preconditionFailure("Even an in-memory store could not be created")
            }
            return fallback
        }
    }
}

/// Launch options for UI tests and debug tooling, passed as `-key value` pairs.
///
/// AppKit and UIKit put such pairs into the `UserDefaults` argument domain. Every flag needs a value:
/// a bare flag would swallow the next key, and AppKit would treat the leftover value as a file to
/// open, which suppresses the app's window.
struct LaunchOptions {
    static let uiTesting = "ui-testing"
    static let presetProfile = "vos-preset-profile"
    static let initialTab = "vos-tab"
    static let aiStub = "vos-ai-stub"
    static let selfTest = "vos-self-test"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isUITesting: Bool { defaults.bool(forKey: Self.uiTesting) }

    /// Replace AI with canned answers so UI tests don't depend on a model (Debug builds only).
    var usesAIStub: Bool { defaults.bool(forKey: Self.aiStub) }

    /// Debug-only end-to-end check to run at launch, e.g. `capture` (see `SelfTest`).
    var selfTest: String? { defaults.string(forKey: Self.selfTest) }

    /// `native:learning1,learning2`, for example `tr:en,de`.
    var presetProfile: LearnerProfile? {
        guard let value = defaults.string(forKey: Self.presetProfile) else { return nil }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let native = LanguageCode(rawValue: parts[0]) else { return nil }
        let learning = parts[1].split(separator: ",").compactMap { LanguageCode(rawValue: String($0)) }
        return try? LearnerProfile(native: native, learning: learning)
    }

    var initialTab: AppTab? {
        defaults.string(forKey: Self.initialTab).flatMap(AppTab.init(rawValue:))
    }
}
