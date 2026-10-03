import CoreGraphics
import Foundation
import VocabularyCore

/// Text recognized on a photographed page (ADR-005): its paragraphs, and words with boxes the learner
/// can tap.
public struct PageText: Sendable {
    /// A recognized word.
    public struct Word: Sendable, Equatable, Identifiable {
        public let id: Int
        /// The word without surrounding punctuation.
        public let text: String
        /// Normalized box (0…1) in the upright image, with the origin at the top left.
        public let box: CGRect
        /// Index into `paragraphs`.
        public let paragraph: Int
        /// The word's index in its paragraph's tokens.
        let token: Int?
    }

    /// A word as the recognizer reported it, before it is matched to the paragraph transcript.
    public struct RecognizedWord: Sendable {
        public var text: String
        public var box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    /// A paragraph as the recognizer reported it: its transcript and its words in reading order.
    public struct RecognizedParagraph: Sendable {
        public var transcript: String
        public var words: [RecognizedWord]

        public init(transcript: String, words: [RecognizedWord]) {
            self.transcript = transcript
            self.words = words
        }
    }

    /// The paragraph transcripts. Lines that wrap inside a sentence are already joined.
    public var paragraphs: [String] { tokenized.map(\.text) }
    public let words: [Word]
    private let tokenized: [TokenizedText]

    public var isEmpty: Bool { words.isEmpty }

    public init(_ recognized: [RecognizedParagraph]) {
        var words: [Word] = []
        var tokenized: [TokenizedText] = []
        for (index, paragraph) in recognized.enumerated() {
            let text = TokenizedText(paragraph.transcript)
            let kept = paragraph.words.compactMap { word -> (core: String, box: CGRect)? in
                let core = word.text.trimmingCharacters(in: Self.trimmed)
                return core.isEmpty ? nil : (core, word.box)
            }
            let tokens = Self.match(kept.map(\.core), to: text.tokens)
            for (word, token) in zip(kept, tokens) {
                words.append(Word(id: words.count, text: word.core, box: word.box, paragraph: index, token: token))
            }
            tokenized.append(text)
        }
        self.words = words
        self.tokenized = tokenized
    }

    /// The sentence that contains the word, the context for its insight. Sentences continue across
    /// line breaks within a paragraph.
    public func sentence(containing word: Word) -> String? {
        guard tokenized.indices.contains(word.paragraph) else { return nil }
        let text = tokenized[word.paragraph]
        guard let token = word.token ?? text.tokens.firstIndex(where: { $0.text == word.text }) else { return nil }
        return text.sentence(containing: token...token)
    }

    /// The word at a point in normalized, top-left-origin coordinates. A tap that just misses every
    /// box still picks the nearest word within `tolerance`.
    public func word(at point: CGPoint, tolerance: CGFloat = 0.02) -> Word? {
        if let hit = words.first(where: { $0.box.contains(point) }) {
            return hit
        }
        let nearest = words.min { Self.distance(from: point, to: $0.box) < Self.distance(from: point, to: $1.box) }
        guard let nearest, Self.distance(from: point, to: nearest.box) <= tolerance else { return nil }
        return nearest
    }

    // MARK: Matching

    private static let trimmed = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)

    /// Matches recognized words to transcript tokens. Both are in reading order, so a word normally
    /// matches one of the next few tokens. A word the recognizer spelled differently from the
    /// transcript then takes the free token between its matched neighbors, instead of jumping to a
    /// later word with the same spelling.
    static func match(_ words: [String], to tokens: [TextToken]) -> [Int?] {
        var result = [Int?](repeating: nil, count: words.count)
        var cursor = 0
        for (index, word) in words.enumerated() {
            let window = cursor..<min(cursor + 3, tokens.count)
            if let found = window.first(where: { tokens[$0].text == word }) {
                result[index] = found
                cursor = found + 1
            }
        }
        var previous = -1
        for index in result.indices {
            if let token = result[index] {
                previous = token
                continue
            }
            let next = result[(index + 1)...].lazy.compactMap { $0 }.first ?? tokens.count
            if previous + 1 < next {
                previous += 1
                result[index] = previous
            }
        }
        return result
    }

    private static func distance(from point: CGPoint, to box: CGRect) -> CGFloat {
        let dx = max(box.minX - point.x, 0, point.x - box.maxX)
        let dy = max(box.minY - point.y, 0, point.y - box.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
