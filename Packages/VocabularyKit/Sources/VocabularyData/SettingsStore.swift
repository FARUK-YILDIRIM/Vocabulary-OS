import Foundation
import Observation
import os
import VocabularyCore

/// The learner's synced settings (ADR-002): profile, AI selection and review limits.
///
/// API keys are deliberately absent. They live only in the Keychain (`VocabularyAI`), and the
/// key-value store is unencrypted.
@MainActor
@Observable
public final class SettingsStore {
    /// Storage keys. The suffix versions the stored JSON shape.
    public enum Key {
        public static let profile = "profile.v1"
        public static let aiSelection = "aiSelection.v1"
        public static let reviewLimits = "reviewLimits.v1"
        public static let customProviders = "customProviders.v1"
        public static let cloudPrivacy = "cloudPrivacyAcknowledged.v1"
        public static let sharesPhotosWithAI = "sharesPhotosWithAI.v1"
        /// Stays on this device: the choice of a provider at this device's own address.
        public static let deviceAISelection = "deviceAISelection.v1"
    }

    public var profile: LearnerProfile? {
        didSet { save(profile, forKey: Key.profile) }
    }

    /// The provider and model in use. Choosing a provider at this device's own address (`localhost`)
    /// changes only this device's choice; every other choice syncs (SPEC C2).
    public var aiSelection: AIProviderSelection {
        get { deviceAISelection ?? sharedAISelection }
        set {
            if customProviders.first(where: { $0.id == newValue.providerID })?.isOnThisDevice == true {
                deviceAISelection = newValue
            } else {
                deviceAISelection = nil
                sharedAISelection = newValue
            }
        }
    }

    /// The choice the learner's devices share.
    private var sharedAISelection: AIProviderSelection {
        didSet { save(sharedAISelection, forKey: Key.aiSelection) }
    }

    /// This device's own choice, which wins over the shared one.
    private var deviceAISelection: AIProviderSelection? {
        didSet { backing.setDeviceData(deviceAISelection.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.deviceAISelection) }
    }

    /// Providers the learner added (SPEC C2). Their keys are in the Keychain, never here.
    public var customProviders: [CustomProvider] {
        didSet { save(customProviders, forKey: Key.customProviders) }
    }

    public var reviewLimits: ReviewLimits {
        didSet { save(reviewLimits, forKey: Key.reviewLimits) }
    }

    /// Whether the learner has seen what is sent to cloud providers (SPEC C2).
    public var hasAcknowledgedCloudPrivacy: Bool {
        didSet { save(hasAcknowledgedCloudPrivacy, forKey: Key.cloudPrivacy) }
    }

    /// Whether object capture may send the photo to a cloud provider (ADR-005). Off until the learner
    /// turns it on; the on-device model never gets it.
    public var sharesPhotosWithAI: Bool {
        didSet { save(sharesPhotosWithAI, forKey: Key.sharesPhotosWithAI) }
    }

    /// Onboarding is done once the learner has a native language and at least one learning language.
    public var isOnboarded: Bool { profile?.isReadyToLearn == true }

    @ObservationIgnored private let backing: any KeyValueBacking
    @ObservationIgnored private var isApplyingExternalChange = false
    @ObservationIgnored private let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyData.logCategory)

    public init(backing: any KeyValueBacking) {
        self.backing = backing
        profile = Self.load(LearnerProfile.self, forKey: Key.profile, from: backing)
        sharedAISelection = Self.load(AIProviderSelection.self, forKey: Key.aiSelection, from: backing) ?? .onDevice
        deviceAISelection = backing.deviceData(forKey: Key.deviceAISelection)
            .flatMap { try? JSONDecoder().decode(AIProviderSelection.self, from: $0) }
        reviewLimits = Self.load(ReviewLimits.self, forKey: Key.reviewLimits, from: backing) ?? ReviewLimits()
        customProviders = Self.load([CustomProvider].self, forKey: Key.customProviders, from: backing) ?? []
        hasAcknowledgedCloudPrivacy = Self.load(Bool.self, forKey: Key.cloudPrivacy, from: backing) ?? false
        sharesPhotosWithAI = Self.load(Bool.self, forKey: Key.sharesPhotosWithAI, from: backing) ?? false
        backing.onExternalChange = { [weak self] keys in
            self?.applyExternalChange(keys)
        }
    }

    /// Removes a provider the learner added. If it was in use, this device goes back to the choice
    /// the other devices share, or to the on-device model when that was the removed provider too.
    public func removeCustomProvider(id: String) {
        customProviders.removeAll { $0.id == id }
        if deviceAISelection?.providerID == id {
            deviceAISelection = nil
        }
        if sharedAISelection.providerID == id {
            sharedAISelection = .onDevice
        }
    }

    private func applyExternalChange(_ keys: [String]) {
        // Assigning below would otherwise write the same values straight back to iCloud.
        isApplyingExternalChange = true
        defer { isApplyingExternalChange = false }
        for key in keys {
            switch key {
            case Key.profile:
                profile = Self.load(LearnerProfile.self, forKey: key, from: backing)
            case Key.aiSelection:
                sharedAISelection = Self.load(AIProviderSelection.self, forKey: key, from: backing) ?? .onDevice
            case Key.reviewLimits:
                reviewLimits = Self.load(ReviewLimits.self, forKey: key, from: backing) ?? ReviewLimits()
            case Key.customProviders:
                customProviders = Self.load([CustomProvider].self, forKey: key, from: backing) ?? []
            case Key.cloudPrivacy:
                hasAcknowledgedCloudPrivacy = Self.load(Bool.self, forKey: key, from: backing) ?? false
            case Key.sharesPhotosWithAI:
                sharesPhotosWithAI = Self.load(Bool.self, forKey: key, from: backing) ?? false
            default:
                continue
            }
        }
    }

    private func save(_ value: (some Encodable)?, forKey key: String) {
        guard !isApplyingExternalChange else { return }
        guard let value else {
            backing.setData(nil, forKey: key)
            return
        }
        do {
            backing.setData(try JSONEncoder().encode(value), forKey: key)
        } catch {
            logger.error("Could not encode setting \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String, from backing: any KeyValueBacking) -> T? {
        guard let data = backing.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // A value written by a newer app version, or corrupted; fall back to the default.
            Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyData.logCategory)
                .warning("Ignoring unreadable setting \(key, privacy: .public)")
            return nil
        }
    }
}
