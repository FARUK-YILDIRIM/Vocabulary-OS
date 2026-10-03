import Foundation
import Observation
import VocabularyCore
import VocabularyData

/// Owns the app's long-lived dependencies and hands them to views through the environment.
@Observable
final class AppModel {
    let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Production wiring. UI tests launch with `-ui-testing YES` to start from a clean, in-memory
    /// state, optionally already onboarded with `-vos-preset-profile tr:en,de`.
    static func live(options: LaunchOptions = LaunchOptions()) -> AppModel {
        guard options.isUITesting else {
            return AppModel(settings: SettingsStore(backing: Self.makeSettingsBacking()))
        }
        let settings = SettingsStore(backing: InMemoryKeyValueBacking())
        settings.profile = options.presetProfile
        return AppModel(settings: settings)
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

    /// For SwiftUI previews: in-memory settings, optionally already onboarded.
    static func preview(profile: LearnerProfile? = try? LearnerProfile(native: .turkish, learning: [.english, .german])) -> AppModel {
        let settings = SettingsStore(backing: InMemoryKeyValueBacking())
        settings.profile = profile
        return AppModel(settings: settings)
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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isUITesting: Bool { defaults.bool(forKey: Self.uiTesting) }

    /// `native:learning1,learning2`, for example `tr:en,de`.
    var presetProfile: LearnerProfile? {
        guard let value = defaults.string(forKey: Self.presetProfile) else { return nil }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let native = LanguageCode(rawValue: parts[0]) else { return nil }
        let learning = parts[1].split(separator: ",").compactMap { LanguageCode(rawValue: String($0)) }
        return try? LearnerProfile(native: native, learning: learning)
    }

    var initialTab: AppTab? {
        switch defaults.string(forKey: Self.initialTab) {
        case "today": .today
        case "library": .library
        case "settings": .settings
        default: nil
        }
    }
}
