import Testing
@testable import VocabularyCore

@Test func logSubsystemIsStable() {
    // Console filters and docs rely on this exact value.
    #expect(VocabularyCore.logSubsystem == "app.vocabularyos")
}
