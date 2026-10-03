import Testing
@testable import VocabularyCore

@Suite struct TokenSelectionTests {
    @Test func firstTapSelectsOneWord() {
        #expect(TokenSelection.afterTap(on: 3, current: nil) == 3...3)
    }

    @Test func tappingTheSelectedWordClearsTheSelection() {
        #expect(TokenSelection.afterTap(on: 3, current: 3...3) == nil)
    }

    @Test func tappingAnotherWordExtendsToAPhraseInEitherDirection() {
        #expect(TokenSelection.afterTap(on: 6, current: 3...3) == 3...6)
        #expect(TokenSelection.afterTap(on: 1, current: 3...3) == 1...3)
    }

    @Test func phrasesAreLimitedInLength() {
        // Too far away to be one expression: start over with the tapped word.
        #expect(TokenSelection.afterTap(on: 20, current: 3...3) == 20...20)
    }

    @Test func tappingAfterAPhraseStartsANewSelection() {
        #expect(TokenSelection.afterTap(on: 5, current: 3...6) == 5...5)
        #expect(TokenSelection.afterTap(on: 9, current: 3...6) == 9...9)
    }
}
