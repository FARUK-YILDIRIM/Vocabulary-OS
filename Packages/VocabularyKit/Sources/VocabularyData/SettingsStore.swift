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
        public static let customProviderBaseURL = "customProviderBaseURL.v1"
        public static let cloudPrivacy = "cloudPrivacyAcknowledged.v1"
        public static let sharesPhotosWithAI = "sharesPhotosWithAI.v1"
    }

    public var profile: LearnerProfile? {
        didSet { save(profile, forKey: Key.profile) }
    }

    public var aiSelection: AIProviderSelection {
        didSet { save(aiSelection, forKey: Key.aiSelection) }
    }

    public var reviewLimits: ReviewLimits {
        didSet { save(reviewLimits, forKey: Key.reviewLimits) }
    }

    /// Address of the learner's own OpenAI-compatible server (Ollama, LM Studio), if any.
    public var customProviderBaseURL: String? {
        didSet { save(customProviderBaseURL, forKey: Key.customProviderBaseURL) }
    }

    /// `customProviderBaseURL` as a URL, ignoring surrounding whitespace.
    public var customProviderURL: URL? {
        customProviderBaseURL.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
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
        aiSelection = Self.load(AIProviderSelection.self, forKey: Key.aiSelection, from: backing) ?? .onDevice
        reviewLimits = Self.load(ReviewLimits.self, forKey: Key.reviewLimits, from: backing) ?? ReviewLimits()
        customProviderBaseURL = Self.load(String.self, forKey: Key.customProviderBaseURL, from: backing)
        hasAcknowledgedCloudPrivacy = Self.load(Bool.self, forKey: Key.cloudPrivacy, from: backing) ?? false
        sharesPhotosWithAI = Self.load(Bool.self, forKey: Key.sharesPhotosWithAI, from: backing) ?? false
        backing.onExternalChange = { [weak self] keys in
            self?.applyExternalChange(keys)
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
                aiSelection = Self.load(AIProviderSelection.self, forKey: key, from: backing) ?? .onDevice
            case Key.reviewLimits:
                reviewLimits = Self.load(ReviewLimits.self, forKey: key, from: backing) ?? ReviewLimits()
            case Key.customProviderBaseURL:
                customProviderBaseURL = Self.load(String.self, forKey: key, from: backing)
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
