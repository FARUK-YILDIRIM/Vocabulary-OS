import Foundation
import Testing
@testable import VocabularyCapture

@Suite struct ObjectClassifierTests {
    @Test func ranksNamedThingsBeforeCategoriesAndDropsWeakLabels() {
        let labels = ObjectClassifier.rank([
            ("utensil", 0.36), ("tableware", 0.36), ("cup", 0.36), ("mug", 0.14), ("drink", 0.12),
        ])
        #expect(labels.first?.identifier == "cup")
        #expect(Set(labels.dropFirst().map(\.identifier)) == ["tableware", "utensil"])
    }

    @Test func keepsAtMostFiveLabelsAndSpellsThemAsWords() {
        let labels = ObjectClassifier.rank([
            ("swivel_chair", 0.9), ("chair", 0.9), ("furniture", 0.9), ("desk", 0.5), ("lamp", 0.4),
            ("computer", 0.35), ("book", 0.31),
        ])
        #expect(labels.map(\.identifier) == ["swivel_chair", "chair", "desk", "lamp", "computer"])
        #expect(labels.first?.name == "swivel chair")
    }

    #if canImport(AppKit)
    @Test func classifiesACupAsACup() async throws {
        let labels = try await ObjectClassifier().labels(for: TestImages.jpeg(TestImages.symbol("cup.and.saucer.fill")))
        #expect(labels.first?.identifier == "cup")
    }
    #endif

    @Test func aBlankImageHasNoLabels() async throws {
        let labels = try await ObjectClassifier().labels(for: TestImages.jpeg(TestImages.blank(width: 600, height: 600)))
        #expect(labels.isEmpty)
    }

    @Test func dataThatIsNotAnImageIsRejected() async {
        await #expect(throws: CaptureError.unreadableImage) {
            try await ObjectClassifier().labels(for: Data("nope".utf8))
        }
    }
}
