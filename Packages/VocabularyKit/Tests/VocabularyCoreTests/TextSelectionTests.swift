import Testing
@testable import VocabularyCore

@Suite struct TokenizedTextTests {
    @Test func splitsASentenceIntoWords() {
        let text = TokenizedText("This website uses cookies for tracking.")
        #expect(text.tokens.map(\.text) == ["This", "website", "uses", "cookies", "for", "tracking"])
    }

    @Test func leavesPunctuationOutOfWords() {
        let text = TokenizedText("Wir saßen auf einer Bank, die alt war.")
        #expect(text.tokens.map(\.text).contains("Bank"))
        #expect(!text.tokens.map(\.text).contains("Bank,"))
    }

    @Test func segmentsCoverTheWholeTextInOrder() {
        let source = "Hello, world! It's fine."
        let text = TokenizedText(source)
        let rebuilt = text.segments.map { segment in
            switch segment {
            case .word(let token): token.text
            case .separator(let separator): separator
            }
        }.joined()
        #expect(rebuilt == source)
    }

    @Test func emptyTextHasNoTokens() {
        #expect(TokenizedText("").tokens.isEmpty)
        #expect(TokenizedText("  \n ").tokens.isEmpty)
    }

    @Test func segmentsJapaneseWithoutSpaces() {
        #expect(TokenizedText("私は本を読みます。").tokens.count > 1)
    }
}

@Suite struct SelectionTests {
    private let cookies = TokenizedText("This website uses cookies for tracking.")

    @Test func termForASingleWord() {
        #expect(cookies.term(for: 3...3) == "cookies")
    }

    @Test func termForASpanKeepsTheOriginalSpacing() throws {
        let text = TokenizedText("Take an umbrella, it's raining cats and dogs.")
        let start = try #require(text.tokens.firstIndex { $0.text == "raining" })
        let end = try #require(text.tokens.firstIndex { $0.text == "dogs" })
        #expect(text.term(for: start...end) == "raining cats and dogs")
    }

    @Test func invalidSelectionsReturnNil() {
        #expect(cookies.term(for: 4...9) == nil)
        #expect(cookies.sentence(containing: 10...10) == nil)
    }

    @Test func sentenceForTheSelection() {
        #expect(cookies.sentence(containing: 3...3) == "This website uses cookies for tracking.")
    }

    @Test func picksTheSentenceThatContainsTheSelectedOccurrence() throws {
        let text = TokenizedText("Ich muss zur Bank. Danach treffe ich sie im Park, wo wir auf einer Bank sitzen.")
        let second = try #require(text.tokens.lastIndex { $0.text == "Bank" })
        #expect(text.sentence(containing: second...second) == "Danach treffe ich sie im Park, wo wir auf einer Bank sitzen.")
    }

    @Test func joinsSentencesThatWrapAcrossLines() throws {
        let text = TokenizedText("He ran the family\ncompany for ten years. Then he retired.")
        let ran = try #require(text.tokens.firstIndex { $0.text == "ran" })
        #expect(text.sentence(containing: ran...ran) == "He ran the family company for ten years.")
    }

    /// Text without sentence punctuation can be a whole page; only the words around the selection
    /// go to the AI with every request (security review).
    @Test func aVeryLongSentenceIsCutDownToTheWordsAroundTheSelection() throws {
        let words = (1...600).map { "word\($0)" }
        let text = TokenizedText(words.joined(separator: " "))
        let index = try #require(text.tokens.firstIndex { $0.text == "word300" })

        let sentence = try #require(text.sentence(containing: index...index))
        #expect(sentence.count <= TokenizedText.maximumSentenceLength)
        #expect(sentence.count > TokenizedText.maximumSentenceLength - 12, "as many words as fit")
        #expect(sentence.contains("word299 word300 word301"))
        #expect(!sentence.hasPrefix(" ") && !sentence.hasSuffix(" "))
        #expect(sentence.split(separator: " ").allSatisfy { $0.hasPrefix("word") }, "only whole words")
    }

    @Test func keepsParagraphBreaksAsSentenceBoundaries() throws {
        let text = TokenizedText("A short heading\n\nThe old man ran the company.")
        let ran = try #require(text.tokens.firstIndex { $0.text == "ran" })
        #expect(text.sentence(containing: ran...ran) == "The old man ran the company.")
    }
}

@Suite struct TermAnalysisTests {
    @Test func lemmatizesEnglishVerbsAndNouns() {
        let ran = TermAnalysis.analyze(term: "ran", in: "He ran the family company for ten years.", language: .english)
        #expect(ran.lemma == "run")
        #expect(ran.partOfSpeech == .verb)

        let cookies = TermAnalysis.analyze(term: "cookies", in: "This website uses cookies for tracking.", language: .english)
        #expect(cookies.lemma == "cookie")
        #expect(cookies.partOfSpeech == .noun)
    }

    @Test func lemmatizesTurkish() {
        let result = TermAnalysis.analyze(term: "kitapları", in: "Kitapları masanın üstüne bıraktım.", language: .turkish)
        #expect(result.lemma == "kitap")
    }

    @Test func returnsNothingWhereTheSchemeIsUnavailable() {
        // NaturalLanguage has no German lemma scheme on macOS 26 (ADR-004); the AI fills it in.
        let result = TermAnalysis.analyze(term: "abzuheben", in: "Ich muss zur Bank, um Geld abzuheben.", language: .german)
        #expect(result.lemma == nil)
    }

    @Test func multiWordTermsAreMarkedAsPhrases() {
        let result = TermAnalysis.analyze(
            term: "raining cats and dogs", in: "Take an umbrella, it's raining cats and dogs.", language: .english
        )
        #expect(result.lemma == nil)
        #expect(result.partOfSpeech == .phrase)
    }

    @Test func worksWithoutASentence() {
        let result = TermAnalysis.analyze(term: "cookies", in: nil, language: .english)
        #expect(result.lemma == "cookie")
    }
}
