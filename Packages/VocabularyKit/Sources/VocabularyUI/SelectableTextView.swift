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
                case .word(let index, let word, let before, let after):
                    // The punctuation touching a word moves with it, so a line never starts with it.
                    HStack(spacing: 0) {
                        if !before.isEmpty { punctuation(before) }
                        WordChip(word: word, isSelected: selection?.contains(index) == true)
                            .onTapGesture { onTap(index) }
                            .accessibilityIdentifier("token-\(index)")
                        if !after.isEmpty { punctuation(after) }
                    }
                case .space(let text):
                    Text(verbatim: text).font(.title3)
                case .lineBreak:
                    Color.clear.frame(width: 0, height: 8).flowLineBreak()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// VoiceOver moves word by word, so punctuation would only interrupt.
    private func punctuation(_ text: String) -> some View {
        Text(verbatim: text).font(.title3).accessibilityHidden(true)
    }

    /// One laid-out piece: a word with the punctuation touching it, the spaces between words, or a
    /// line break.
    struct Piece: Identifiable {
        enum Kind {
            case word(index: Int, text: String, before: String, after: String)
            case space(String)
            case lineBreak
        }

        let id: Int
        let kind: Kind

        static func make(from text: TokenizedText) -> [Piece] {
            var pieces: [Piece] = []
            var wordIndex = 0
            var before = ""
            let segments = text.segments
            for (position, segment) in segments.enumerated() {
                switch segment {
                case .word(let token):
                    pieces.append(Piece(id: pieces.count, kind: .word(index: wordIndex, text: token.text, before: before, after: "")))
                    before = ""
                    wordIndex += 1
                case .separator(let separator):
                    var rest = Substring(separator)
                    // Punctuation right after a word ("cookies,") ends that word's piece.
                    let after = rest.prefix { !$0.isWhitespace }
                    if !after.isEmpty, let last = pieces.indices.last, case .word(let index, let word, let wordBefore, let wordAfter) = pieces[last].kind {
                        pieces[last] = Piece(id: pieces[last].id, kind: .word(index: index, text: word, before: wordBefore, after: wordAfter + after))
                        rest = rest.dropFirst(after.count)
                    }
                    // Punctuation right before a word ("«hallo") starts the next word's piece.
                    if segments.indices.contains(position + 1), case .word = segments[position + 1] {
                        let leading = rest.reversed().prefix { !$0.isWhitespace }.count
                        before = String(rest.suffix(leading))
                        rest = rest.dropLast(leading)
                    }
                    let lines = rest.split(separator: "\n", omittingEmptySubsequences: false)
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
