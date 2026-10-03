import Testing
@testable import VocabularyUI

// VocabularyUI defaults to MainActor isolation (ADR-006), so its tests run on the main actor too.
@Test @MainActor func logCategoryNamesTheModule() {
    #expect(VocabularyUI.logCategory == "ui")
}
