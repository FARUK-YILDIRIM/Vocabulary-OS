import Foundation
import Observation
import os
import SwiftData
import UserNotifications
import VocabularyAI
import VocabularyCore
import VocabularyData
import VocabularySpeech

/// Owns the app's long-lived dependencies and hands them to views through the environment.
@Observable
final class AppModel {
    let settings: SettingsStore
    let container: ModelContainer
    let repository: WordRepository
    let reviews: ReviewRepository
    let quizzes: QuizRepository
    let podcasts: PodcastRepository
    let plans: PlanRepository
    /// Schedules the study plans' reminders on this device (SPEC C10).
    let reminders = PlanNotificationScheduler(center: SystemNotificationCenter())
    let navigation: AppNavigation
    /// Speaks words, listening questions and podcasts with on-device voices (ADR-008).
    let speech = SpeechPlayer()
    let secrets: any SecretStore
    let router: ProviderRouter
    /// Words saved in the Share extension, waiting to be imported; `nil` without an App Group.
    let inbox: CaptureInbox?
    @ObservationIgnored private let options: LaunchOptions

    init(
        settings: SettingsStore,
        container: ModelContainer,
        secrets: any SecretStore,
        inbox: CaptureInbox? = nil,
        options: LaunchOptions = LaunchOptions()
    ) {
        self.settings = settings
        self.container = container
        let repository = WordRepository(container: container)
        self.repository = repository
        self.reviews = ReviewRepository(words: repository)
        self.quizzes = QuizRepository(words: repository)
        self.podcasts = PodcastRepository(words: repository)
        self.plans = PlanRepository(words: repository)
        self.navigation = AppNavigation(tab: options.initialTab ?? .today)
        self.secrets = secrets
        self.router = ProviderRouter(secrets: secrets)
        self.inbox = inbox
        self.options = options
    }

    /// The App Group shared with the Share extension, named in Info.plist (ADR-002). `nil` in builds
    /// without it, such as unsigned Mac builds.
    static var appGroup: AppGroup? {
        (Bundle.main.object(forInfoDictionaryKey: "VOSAppGroupIdentifier") as? String).flatMap(AppGroup.init(identifier:))
    }

    /// The App Group's defaults, which hold the settings mirror the Share extension reads (ADR-002),
    /// or the app's own defaults when there is no App Group.
    static var sharedDefaults: UserDefaults {
        appGroup?.defaults ?? .standard
    }

    /// Production wiring. UI tests launch with `-ui-testing YES` to start from a clean, in-memory
    /// state, optionally already onboarded with `-vos-preset-profile tr:en,de`.
    static func live(options: LaunchOptions = LaunchOptions()) -> AppModel {
        #if DEBUG
        ShareExtensionTestHooks(usesAIStub: options.usesAIStub, profile: options.isUITesting ? options.presetProfile : nil)
            .save(to: sharedDefaults)
        #endif
        if options.isUITesting {
            let settings = SettingsStore(backing: InMemoryKeyValueBacking())
            settings.profile = options.presetProfile
            let model = AppModel(
                settings: settings,
                container: makeContainer(inMemory: true),
                secrets: InMemorySecretStore(),
                inbox: appGroup?.inbox,
                options: options
            )
            #if DEBUG
            if options.seedsLibrary {
                SampleLibrary.seed(into: model.repository)
            }
            #endif
            return model
        }
        return AppModel(
            settings: SettingsStore(backing: makeSettingsBacking()),
            container: makeContainer(inMemory: false),
            secrets: KeychainSecretStore(accessGroup: appGroup?.identifier),
            inbox: appGroup?.inbox,
            options: options
        )
    }

    /// For SwiftUI previews: in-memory settings and store, optionally already onboarded.
    static func preview(profile: LearnerProfile? = try? LearnerProfile(native: .turkish, learning: [.english, .german])) -> AppModel {
        let settings = SettingsStore(backing: InMemoryKeyValueBacking())
        settings.profile = profile
        return AppModel(settings: settings, container: makeContainer(inMemory: true), secrets: InMemorySecretStore())
    }

    // MARK: AI

    /// The insight service for the learner's current provider, built at the moment of use so a newly
    /// saved key or model takes effect immediately.
    func makeInsightService() -> InsightService {
        #if DEBUG
        if options.usesAIStub {
            return InsightService(client: StubGenerationClient(), strategy: .stepwise, source: InsightSource(providerID: "stub"))
        }
        #endif
        return router.insightService(for: settings.aiSelection, customBaseURL: customBaseURL)
    }

    var customBaseURL: URL? {
        settings.customProviderURL
    }

    /// Whether object capture sends the photo with the request: the learner allowed it and a cloud
    /// provider is in use; the on-device model reads text only (ADR-005).
    var sendsPhotosToAI: Bool {
        settings.sharesPhotosWithAI && router.provider(for: settings.aiSelection).kind != .appleOnDevice
    }

    var providerDisplayName: String {
        router.displayName(for: settings.aiSelection)
    }

    /// The name shown under an insight for the provider that produced it.
    func providerName(for providerID: String) -> String {
        if providerID == "stub" { return String(localized: "Test answers") }
        return ProviderCatalog.provider(id: providerID)?.displayName ?? providerID
    }

    // MARK: Plans

    /// Plans in the learner's languages: removing a language pauses its plans, and adding it back
    /// resumes them (SPEC C1, C10).
    func activePlans() throws -> [StudyPlan] {
        let learning = Set(settings.profile?.learning ?? [])
        return try plans.plans().filter { $0.language.map(learning.contains) == true }
    }

    /// Makes this device's reminders match the plans (SPEC C10).
    func rescheduleReminders() async {
        do {
            await reminders.reconcile(try activePlans()) { PlanText.reminder(for: $0) }
        } catch {
            Logger(subsystem: VocabularyCore.logSubsystem, category: "app")
                .error("Could not read the study plans: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Asks once whether plans may send reminders; later calls return the learner's answer.
    @discardableResult
    func requestReminderPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Whether the learner turned notifications off for the app.
    func remindersAreDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Opens a `vocabularyos://` link, where a plan's link starts its activity (SPEC C10), or a
    /// `.vocabularyos` word list file to import (SPEC C11).
    func open(_ url: URL) {
        if url.isFileURL {
            openWordList(at: url)
            return
        }
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .plan(let id):
            guard let plan = try? activePlans().first(where: { $0.id == id }) else { return }
            navigation.start(plan)
        }
    }

    // MARK: Share extension

    /// Moves words saved in the Share extension into the library (ADR-002).
    func importInbox() {
        guard let inbox else { return }
        CaptureInbox.importPending(from: inbox, into: repository)
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
        UbiquitousKeyValueBacking(cloud: NSUbiquitousKeyValueStore.default, mirror: sharedDefaults)
        #else
        UbiquitousKeyValueBacking(cloud: nil, mirror: sharedDefaults)
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
    static let seedLibrary = "vos-seed-library"
    static let captureMode = "vos-capture-mode"
    static let samplePage = "vos-sample-page"
    static let sampleObject = "vos-sample-object"
    static let podcast = "vos-podcast"
    static let remindIn = "vos-remind-in"
    static let importSample = "vos-import-sample"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isUITesting: Bool { defaults.bool(forKey: Self.uiTesting) }

    /// Replace AI with canned answers so UI tests don't depend on a model (Debug builds only).
    var usesAIStub: Bool { defaults.bool(forKey: Self.aiStub) }

    /// Fill the in-memory library with sample words (Debug builds only, see `SampleLibrary`).
    var seedsLibrary: Bool { defaults.bool(forKey: Self.seedLibrary) }

    /// Open Capture in this mode, e.g. `page`.
    var captureMode: CaptureScreen.Mode? {
        defaults.string(forKey: Self.captureMode).flatMap(CaptureScreen.Mode.init(rawValue:))
    }

    /// Load a generated book page into page capture (Debug builds only, see `SamplePage`).
    var usesSamplePage: Bool { defaults.bool(forKey: Self.samplePage) }

    /// Load a stand-in photo of a cup into object capture (Debug builds only, see `SampleObject`).
    var usesSampleObject: Bool { defaults.bool(forKey: Self.sampleObject) }

    /// Open Practice → New Podcast (`new`) or the newest episode (`newest`), for screenshots (Debug
    /// builds only).
    var podcastScreen: String? { defaults.string(forKey: Self.podcast) }

    /// Sends the first plan's reminder this many seconds after launch, for UI tests (Debug builds
    /// only).
    var remindInSeconds: Int? {
        defaults.object(forKey: Self.remindIn) == nil ? nil : defaults.integer(forKey: Self.remindIn)
    }

    /// Opens a sample word list file at launch, as if the learner had opened it (Debug builds only).
    var importsSample: Bool { defaults.bool(forKey: Self.importSample) }

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
