import Foundation
import Testing
@testable import VocabularyData

@Suite struct AppGroupTests {
    /// The test runner has no App Group entitlement, like an unsigned Mac build. On macOS the
    /// container URL comes back anyway, and touching it would make macOS ask the user for access.
    @Test func aProcessWithoutTheEntitlementGetsNoGroup() {
        #expect(AppGroup(identifier: "group.app.vocabularyos.tests") == nil)
    }

    @Test func theInboxLivesInTheGroupContainer() {
        let group = AppGroup(identifier: "group.app.vocabularyos.tests", containerURL: URL(filePath: "/tmp/group"))
        #expect(group.inbox.directory == URL(filePath: "/tmp/group/Inbox", directoryHint: .isDirectory))
    }
}
