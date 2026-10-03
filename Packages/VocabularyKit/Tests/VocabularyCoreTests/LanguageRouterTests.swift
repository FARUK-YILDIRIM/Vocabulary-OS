import Testing
@testable import VocabularyCore

/// Expectations follow the NLLanguageRecognizer measurements recorded in ADR-004 (macOS 26.5).
@Suite struct LanguageRouterTests {
    private let router = LanguageRouter()
    private let turkishLearningEnglishAndGerman = try! LearnerProfile(native: .turkish, learning: [.english, .german])

    @Test func sentencesInALearningLanguageAreConfident() {
        #expect(router.route("Wir saßen auf einer Bank im Park.", profile: turkishLearningEnglishAndGerman) == .confident(.german))
        #expect(router.route("This website uses cookies for tracking.", profile: turkishLearningEnglishAndGerman) == .confident(.english))
    }

    @Test func singleWordsThatExistInSeveralLanguagesAreAmbiguous() {
        #expect(router.route("Hand", profile: turkishLearningEnglishAndGerman) == .ambiguous([.english, .german]))
        #expect(router.route("Kind", profile: turkishLearningEnglishAndGerman) == .ambiguous([.english, .german]))
        // "Bank" scores 0.83 for English, too low for a lone word: the learner may mean German.
        #expect(router.route("Bank", profile: turkishLearningEnglishAndGerman) == .ambiguous([.english, .german]))
    }

    @Test func distinctiveSingleWordsAreConfident() {
        #expect(router.route("Schlüssel", profile: turkishLearningEnglishAndGerman) == .confident(.german))
    }

    @Test func sentencesInAnotherCatalogLanguageSuggestAddingIt() {
        #expect(router.route("Je voudrais un café, s'il vous plaît.", profile: turkishLearningEnglishAndGerman) == .notLearning(.french))
    }

    @Test func nativeLanguageTextAsksWhichLearningLanguageToUse() {
        #expect(router.route("Kitapları masanın üstüne bıraktım.", profile: turkishLearningEnglishAndGerman) == .ambiguous([.english, .german]))
    }

    @Test func aSingleLearningLanguageNeedsNoQuestionForShortText() throws {
        let profile = try LearnerProfile(native: .turkish, learning: [.english])
        #expect(router.route("Bank", profile: profile) == .confident(.english))
    }

    @Test func emptyTextFallsBackToTheLearningLanguages() {
        #expect(router.route("   ", profile: turkishLearningEnglishAndGerman) == .ambiguous([.english, .german]))
    }

    @Test func ambiguousResultsPutTheLikeliestLanguageFirst() throws {
        let profile = try LearnerProfile(native: .turkish, learning: [.german, .english])
        // Learning order is German first, but the recognizer prefers English for "cookie".
        #expect(router.route("cookie", profile: profile) == .ambiguous([.english, .german]))
    }
}
