#if DEBUG
import Foundation
import VocabularyCore

/// Test hooks the app hands to the Share extension, which can't receive launch arguments.
/// Debug builds only.
///
/// The app writes them at every launch from its `LaunchOptions` and removes them when no option is
/// set, so a normal run never leaves them behind.
struct ShareExtensionTestHooks: Codable, Equatable {
    private static let key = "vos.debug.shareExtension"

    /// Canned AI answers, as `-vos-ai-stub YES` gives the app.
    var usesAIStub = false
    /// A profile to use instead of the shared settings, which UI tests keep in memory.
    var profile: LearnerProfile?

    static func load(from defaults: UserDefaults) -> ShareExtensionTestHooks? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save(to defaults: UserDefaults) {
        if self == ShareExtensionTestHooks() {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
#endif
