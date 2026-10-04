import Foundation
import Observation
import VocabularyAI
import VocabularyCore
import VocabularyData
import VocabularyUI

/// The Share extension's dependencies, rebuilt from what the app shares through the App Group
/// (ADR-002): the settings mirror, the API keys in the Keychain access group, and the inbox.
@Observable
final class ShareSession {
    enum State {
        case loading
        case capturing(CaptureModel)
        /// The learner hasn't chosen languages in the app yet.
        case needsOnboarding
        /// No App Group container, so words can't be handed to the app.
        case unavailable
    }

    private(set) var state = State.loading
    @ObservationIgnored private var settings: SettingsStore
    @ObservationIgnored private let inbox: CaptureInbox?
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private var usesAIStub = false

    init() {
        let group = (Bundle.main.object(forInfoDictionaryKey: "VOSAppGroupIdentifier") as? String)
            .flatMap(AppGroup.init(identifier:))
        let defaults = group?.defaults ?? .standard
        // The extension only reads settings: values it wrote would never reach iCloud.
        settings = SettingsStore(backing: UbiquitousKeyValueBacking(cloud: nil, mirror: defaults))
        inbox = group?.inbox
        secrets = KeychainSecretStore(accessGroup: group?.identifier)
        #if DEBUG
        applyTestHooks(from: defaults)
        #endif
    }

    #if DEBUG
    /// Canned answers and the UI-test profile, handed over by the app (`ShareExtensionTestHooks`).
    private func applyTestHooks(from defaults: UserDefaults) {
        guard let hooks = ShareExtensionTestHooks.load(from: defaults) else { return }
        usesAIStub = hooks.usesAIStub
        if let profile = hooks.profile {
            settings = SettingsStore(backing: InMemoryKeyValueBacking())
            settings.profile = profile
        }
    }
    #endif

    /// The name shown under an insight.
    var providerName: String {
        usesAIStub ? String(localized: "Test answers") : Self.router(secrets: secrets, settings: settings).displayName(for: settings.aiSelection)
    }

    func start(with text: String) {
        guard let inbox else {
            state = .unavailable
            return
        }
        guard settings.isOnboarded else {
            state = .needsOnboarding
            return
        }
        // Captured by value, so the model's closure doesn't keep the session alive.
        let secrets = secrets, settings = settings, usesAIStub = usesAIStub
        state = .capturing(CaptureModel(
            text: text,
            captureSource: .shareSheet,
            settings: settings,
            destination: InboxCaptureDestination(inbox: inbox)
        ) {
            Self.insightService(secrets: secrets, settings: settings, usesAIStub: usesAIStub)
        })
    }

    /// Knows the providers the learner added in the app.
    private static func router(secrets: any SecretStore, settings: SettingsStore) -> ProviderRouter {
        ProviderRouter(secrets: secrets, customProviders: settings.customProviders)
    }

    /// Built at the moment of use, like the app's, so the current provider and key apply.
    private static func insightService(secrets: any SecretStore, settings: SettingsStore, usesAIStub: Bool) -> InsightService {
        #if DEBUG
        if usesAIStub {
            return InsightService(client: StubGenerationClient(), strategy: .stepwise, source: InsightSource(providerID: "stub"))
        }
        #endif
        return router(secrets: secrets, settings: settings).insightService(for: settings.aiSelection)
    }
}
