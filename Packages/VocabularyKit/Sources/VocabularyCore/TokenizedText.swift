import Foundation
import NaturalLanguage

/// A word the learner can tap, with its position in the source text.
public struct TextToken: Hashable, Sendable {
    public let text: String
    public let range: Range<String.Index>
}

/// A piece of the source text: a selectable word, or the spaces and punctuation between words.
public enum TextSegment: Hashable, Sendable {
    case word(TextToken)
    case separator(String)
}

/// Text split into selectable words, with helpers to turn a selection into a term and its sentence
/// (SPEC C5, ADR-005).
public struct TokenizedText: Sendable {
    public let text: String
    /// Word tokens only, in reading order. Selections are index ranges into this array.
    public let tokens: [TextToken]
    /// The whole text in order, words interleaved with separators; joining it gives back `text`.
    public let segments: [TextSegment]

    public init(_ text: String) {
        self.text = text
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [TextToken] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(TextToken(text: String(text[range]), range: range))
            return true
        }
        self.tokens = tokens

        var segments: [TextSegment] = []
        var cursor = text.startIndex
        for token in tokens {
            if cursor < token.range.lowerBound {
                segments.append(.separator(String(text[cursor..<token.range.lowerBound])))
            }
            segments.append(.word(token))
            cursor = token.range.upperBound
        }
        if cursor < text.endIndex {
            segments.append(.separator(String(text[cursor...])))
        }
        self.segments = segments
    }

    /// The selected word or phrase as written, or `nil` if the selection is out of bounds.
    public func term(for selection: ClosedRange<Int>) -> String? {
        guard tokens.indices.contains(selection.lowerBound), tokens.indices.contains(selection.upperBound) else {
            return nil
        }
        let range = tokens[selection.lowerBound].range.lowerBound..<tokens[selection.upperBound].range.upperBound
        return Self.collapsingWhitespace(String(text[range]))
    }

    /// The sentence that contains the selection, used as the context for AI insight.
    ///
    /// A single line break counts as a space, because recognized and pasted text often wraps
    /// mid-sentence; a blank line ends the paragraph and therefore the sentence.
    public func sentence(containing selection: ClosedRange<Int>) -> String? {
        guard tokens.indices.contains(selection.lowerBound), tokens.indices.contains(selection.upperBound) else {
            return nil
        }
        let flattened = Self.flatteningSingleLineBreaks(text)
        let anchor = String.Index(utf16Offset: tokens[selection.lowerBound].range.lowerBound.utf16Offset(in: text), in: flattened)
        let paragraph = Self.paragraphRange(around: anchor, in: flattened)

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = flattened
        var match: Range<String.Index>?
        tokenizer.enumerateTokens(in: paragraph) { range, _ in
            if range.contains(anchor) {
                match = range
                return false
            }
            return true
        }
        guard let match else { return nil }
        return Self.collapsingWhitespace(String(flattened[match]))
    }

    /// Replaces each line break that is not part of a blank line with a space. Every replacement
    /// keeps the UTF-16 length, so offsets stay valid between the two strings.
    private static func flatteningSingleLineBreaks(_ text: String) -> String {
        var units = Array(text.utf16)
        let newline: UInt16 = 0x0A, carriageReturn: UInt16 = 0x0D, space: UInt16 = 0x20
        for index in units.indices where units[index] == carriageReturn {
            units[index] = space
        }
        for index in units.indices where units[index] == newline {
            let previousIsNewline = index > 0 && units[index - 1] == newline
            let nextIsNewline = index + 1 < units.count && units[index + 1] == newline
            if !previousIsNewline && !nextIsNewline {
                units[index] = space
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// The range between the nearest blank lines around `index`.
    private static func paragraphRange(around index: String.Index, in text: String) -> Range<String.Index> {
        let start = text[..<index].range(of: "\n\n", options: .backwards)?.upperBound ?? text.startIndex
        let end = text[index...].range(of: "\n\n")?.lowerBound ?? text.endIndex
        return start..<end
    }

    private static func collapsingWhitespace(_ string: String) -> String {
        string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
