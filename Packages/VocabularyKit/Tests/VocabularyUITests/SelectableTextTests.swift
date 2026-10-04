import Testing
import VocabularyCore
@testable import VocabularyUI

@Suite struct SelectableTextTests {
    /// Words with the punctuation that touches them; spaces and line breaks between them.
    private func layout(_ text: String) -> [String] {
        SelectableTextView.Piece.make(from: TokenizedText(text)).map { piece in
            switch piece.kind {
            case .word(_, let word, let before, let after): "[\(before)\(word)\(after)]"
            case .space(let space): space
            case .lineBreak: "⏎"
            }
        }
    }

    /// A line can only break where there is a space, so punctuation never starts a line.
    @Test func punctuationStaysWithItsWord() {
        #expect(layout("Cookies, please.") == ["[Cookies,]", " ", "[please.]"])
        #expect(layout("He said «hallo» (twice)!") == ["[He]", " ", "[said]", " ", "[«hallo»]", " ", "[(twice)!]"])
    }

    @Test func keepsSpacesAndLineBreaks() {
        #expect(layout("One.\n\nTwo") == ["[One.]", "⏎", "⏎", "[Two]"])
        #expect(layout("A - B") == ["[A]", " - ", "[B]"])
    }

    @Test func numbersEveryWordInOrder() {
        let indices = SelectableTextView.Piece.make(from: TokenizedText("Wait, what?")).compactMap { piece -> Int? in
            if case .word(let index, _, _, _) = piece.kind { return index }
            return nil
        }
        #expect(indices == [0, 1])
    }
}
