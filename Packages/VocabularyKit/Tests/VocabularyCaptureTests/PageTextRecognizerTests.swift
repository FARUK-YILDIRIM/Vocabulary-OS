import CoreGraphics
import Foundation
import ImageIO
import Testing
import Vision
import VocabularyCore
@testable import VocabularyCapture

@Suite struct PageTextRecognizerTests {
    private let recognizer = PageTextRecognizer()

    private func recognizePage(exifOrientation: Int? = nil, rotated: Bool = false) async throws -> PageText {
        var image = TestImages.page(TestImages.germanAndEnglishPage)
        if rotated {
            image = TestImages.rotatedClockwise(image)
        }
        return try await recognizer.recognize(TestImages.jpeg(image, exifOrientation: exifOrientation), languages: [.german, .english])
    }

    private func words(_ text: String, in page: PageText) -> [PageText.Word] {
        page.words.filter { $0.text == text }
    }

    @Test func findsTheSentenceOfEachOccurrenceOfARepeatedGermanWord() async throws {
        let page = try await recognizePage()
        let banks = words("Bank", in: page)
        try #require(banks.count == 2)

        #expect(page.sentence(containing: banks[0]) == "Ich muss heute noch zur Bank, um Geld abzuheben.")
        // This sentence wraps across two lines on the page.
        #expect(page.sentence(containing: banks[1]) == "Danach treffe ich meine Freundin im Park, wo wir auf einer alten Bank sitzen und reden.")
    }

    @Test func findsTheSentenceInTheEnglishParagraph() async throws {
        let page = try await recognizePage()
        let ran = try #require(words("ran", in: page).first)
        let raining = try #require(words("raining", in: page).first)

        #expect(page.paragraphs.count == 2)
        #expect(ran.paragraph == 1)
        #expect(page.sentence(containing: ran) == "The old man ran the family company for ten years.")
        #expect(page.sentence(containing: raining) == "Every morning he walked to the office, even when it was raining cats and dogs.")
    }

    @Test func wordBoxesUseATopLeftOriginAndHitTesting() async throws {
        let page = try await recognizePage()
        let first = try #require(words("Ich", in: page).first)
        let dogs = try #require(words("dogs", in: page).first)

        #expect(first.box.minY < 0.2, "The first line is near the top of the page")
        #expect(dogs.box.minY > first.box.minY)
        #expect(page.word(at: CGPoint(x: dogs.box.midX, y: dogs.box.midY)) == dogs)
        #expect(page.word(at: CGPoint(x: 0.02, y: 0.98)) == nil, "The bottom corner of the page is empty")
    }

    @Test func boxesMatchTheUprightPhotoWhenTheFileIsRotated() async throws {
        let upright = try await recognizePage()
        // Pixels stored sideways, with EXIF orientation 8 saying how to turn them upright.
        let sideways = try await recognizePage(exifOrientation: 8, rotated: true)
        let expected = try #require(words("Park", in: upright).first).box
        let actual = try #require(words("Park", in: sideways).first).box

        #expect(abs(actual.midX - expected.midX) < 0.01)
        #expect(abs(actual.midY - expected.midY) < 0.01)
    }

    @Test func aBlankImageHasNoText() async throws {
        let page = try await recognizer.recognize(TestImages.jpeg(TestImages.blank(width: 800, height: 600)), languages: [.english])
        #expect(page.isEmpty)
    }

    @Test func everyCatalogLanguageGuidesRecognition() {
        let available = RecognizeDocumentsRequest().supportedRecognitionLanguages
        #expect(PageTextRecognizer.supported(LanguageCatalog.all, by: available).count == LanguageCatalog.all.count)
        #expect(PageTextRecognizer.supported([.chineseTraditional], by: available).first?.script?.identifier == "Hant")
        #expect(PageTextRecognizer.supported([.turkish], by: available).first?.languageCode?.identifier == "tr")
    }

    @Test func dataThatIsNotAnImageIsRejected() async {
        await #expect(throws: CaptureError.unreadableImage) {
            try await recognizer.recognize(Data("not an image".utf8), languages: [.english])
        }
    }
}

@Suite struct PageTextTests {
    private func page(_ transcript: String, words: [String]) -> PageText {
        let recognized = words.enumerated().map { index, word in
            PageText.RecognizedWord(text: word, box: CGRect(x: 0.1 * Double(index % 8), y: 0.1 * Double(index / 8), width: 0.08, height: 0.05))
        }
        return PageText([PageText.RecognizedParagraph(transcript: transcript, words: recognized)])
    }

    @Test func matchesRepeatedWordsInReadingOrderAndTrimsPunctuation() {
        let text = page("Zur Bank. Auf der Bank sitzen.", words: ["Zur", "Bank.", "Auf", "der", "Bank", "sitzen."])

        #expect(text.words.map(\.text) == ["Zur", "Bank", "Auf", "der", "Bank", "sitzen"])
        #expect(text.sentence(containing: text.words[1]) == "Zur Bank.")
        #expect(text.sentence(containing: text.words[4]) == "Auf der Bank sitzen.")
    }

    @Test func keepsWordsTheTranscriptSpellsDifferently() {
        // OCR can read a word differently in the word list than in the paragraph transcript.
        let text = page("The c0okies are fresh. Buy cookies now.", words: ["The", "cookies", "are", "fresh.", "Buy", "cookies", "now."])

        #expect(text.words.count == 7)
        #expect(text.sentence(containing: text.words[1]) == "The c0okies are fresh.")
        #expect(text.sentence(containing: text.words[5]) == "Buy cookies now.")
    }

    @Test func skipsPunctuationOnlyWords() {
        let text = page("Wait — what?", words: ["Wait", "—", "what?"])
        #expect(text.words.map(\.text) == ["Wait", "what"])
    }
}
