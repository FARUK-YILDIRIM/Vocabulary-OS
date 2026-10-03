import Foundation
#if os(macOS)
import Security
#endif

/// The App Group the app shares with its Share extension (ADR-002): the settings mirror, the inbox,
/// and the keychain access group for API keys.
public struct AppGroup: Sendable {
    public let identifier: String
    public let containerURL: URL

    /// `nil` when this process isn't entitled to the group, as in unsigned Mac builds.
    ///
    /// On macOS the entitlement check must come first: the container URL is returned even for a
    /// group the process doesn't belong to, and touching that container makes macOS ask the user
    /// for access.
    public init?(identifier: String) {
        #if os(macOS)
        guard Self.isEntitled(to: identifier) else { return nil }
        #endif
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        self.init(identifier: identifier, containerURL: url)
    }

    init(identifier: String, containerURL: URL) {
        self.identifier = identifier
        self.containerURL = containerURL
    }

    /// Defaults shared by every process in the group.
    public var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// Words saved in the Share extension, waiting for the app.
    public var inbox: CaptureInbox {
        CaptureInbox(directory: containerURL.appending(path: "Inbox", directoryHint: .isDirectory))
    }

    #if os(macOS)
    private static func isEntitled(to identifier: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String]
        else {
            return false
        }
        return groups.contains(identifier)
    }
    #endif
}
