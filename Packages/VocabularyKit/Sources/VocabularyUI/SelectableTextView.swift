import SwiftUI
import VocabularyCore

/// Shows text with every word tappable; the selection follows `TokenSelection` (SPEC C5).
public struct SelectableTextView: View {
    private let pieces: [Piece]
    private let selection: ClosedRange<Int>?
    private let onTap: (Int) -> Void

    public init(text: TokenizedText, selection: ClosedRange<Int>?, onTap: @escaping (Int) -> Void) {
        self.pieces = Piece.make(from: text)
        self.selection = selection
        self.onTap = onTap
    }

    public var body: some View {
        FlowLayout(lineSpacing: 4) {
            ForEach(pieces) { piece in
                switch piece.kind {
                case .word(let index, let word):
                    WordChip(word: word, isSelected: selection?.contains(index) == true)
                        .onTapGesture { onTap(index) }
                        .accessibilityIdentifier("token-\(index)")
                case .space(let text):
                    Text(verbatim: text).font(.title3)
                case .lineBreak:
                    Color.clear.frame(width: 0, height: 8).flowLineBreak()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One laid-out piece: a word, the punctuation or spaces after it, or a line break.
    private struct Piece: Identifiable {
        enum Kind {
            case word(index: Int, text: String)
            case space(String)
            case lineBreak
        }

        let id: Int
        let kind: Kind

        static func make(from text: TokenizedText) -> [Piece] {
            var pieces: [Piece] = []
            var wordIndex = 0
            for segment in text.segments {
                switch segment {
                case .word(let token):
                    pieces.append(Piece(id: pieces.count, kind: .word(index: wordIndex, text: token.text)))
                    wordIndex += 1
                case .separator(let separator):
                    let lines = separator.split(separator: "\n", omittingEmptySubsequences: false)
                    for (offset, line) in lines.enumerated() {
                        if offset > 0 {
                            pieces.append(Piece(id: pieces.count, kind: .lineBreak))
                        }
                        if !line.isEmpty {
                            pieces.append(Piece(id: pieces.count, kind: .space(String(line))))
                        }
                    }
                }
            }
            return pieces
        }
    }
}

private struct WordChip: View {
    let word: String
    let isSelected: Bool

    var body: some View {
        Text(verbatim: word)
            .font(.title3)
            // The highlight extends past the word without changing its layout, so words and
            // punctuation keep their natural text spacing.
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.22))
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .padding(.horizontal, -3)
                        .padding(.vertical, -1)
                }
            }
            .contentShape(.rect.inset(by: -3))
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: word))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    SelectableTextView(
        text: TokenizedText("This website uses cookies for tracking.\n\nTake an umbrella, it's raining cats and dogs."),
        selection: 3...3,
        onTap: { _ in }
    )
    .padding()
}
