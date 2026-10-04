#if DEBUG
import Foundation
import VocabularyCore
import VocabularyData

/// Sample words, a podcast episode and a study plan for UI tests and screenshots
/// (`-vos-seed-library YES`, Debug builds only).
enum SampleLibrary {
    /// The sample plans' IDs, so UI tests can open `vocabularyos://plan/<id>`.
    static let quizPlanID = UUID(uuidString: "5A3F1E2D-7C4B-4E8A-9F60-1B2C3D4E5F60")!
    static let podcastPlanID = UUID(uuidString: "5A3F1E2D-7C4B-4E8A-9F60-1B2C3D4E5F61")!

    @MainActor
    static func seed(into repository: WordRepository, now: Date = .now) {
        let source = InsightSource(providerID: AIProviderSelection.onDevice.providerID)
        func word(_ term: String, _ lemma: String, _ pos: PartOfSpeech, _ language: LanguageCode, _ context: String, _ translation: String, _ meaning: String) -> WordInsight {
            WordInsight(term: term, lemma: lemma, partOfSpeech: pos, language: language, nativeLanguage: .turkish,
                        context: context, translation: translation, meaning: meaning, source: source)
        }
        let words: [(WordInsight, CardState?, Bool)] = [
            (word("cookies", "cookie", .noun, .english, "This website uses cookies for tracking.", "çerez", "Web sitelerinin tarayıcıda sakladığı küçük veri dosyası."), nil, false),
            (word("pitch", "pitch", .noun, .english, "She gave a great pitch to the investors.", "sunum", "Bir fikri ikna edici biçimde anlatan kısa konuşma."),
             CardState(ease: 2.5, intervalDays: 6, repetitions: 2, dueAt: now.addingTimeInterval(-3_600), lastReviewedAt: now.addingTimeInterval(-6 * 86_400)), true),
            (word("ran", "run", .verb, .english, "He ran the family company for ten years.", "yönetmek", "Bir işletmenin başında olmak, onu idare etmek."),
             CardState(ease: 2.6, intervalDays: 30, repetitions: 5, dueAt: now.addingTimeInterval(20 * 86_400), lastReviewedAt: now.addingTimeInterval(-10 * 86_400)), false),
            (word("raining cats and dogs", "raining cats and dogs", .phrase, .english, "Take an umbrella, it's raining cats and dogs.", "bardaktan boşanırcasına", "Çok şiddetli yağmur yağmak."), nil, false),
            (word("Bank", "Bank", .noun, .german, "Wir saßen auf einer Bank im Park.", "bank", "Parklarda oturmak için yapılmış uzun oturak."), nil, false),
            (word("Schlüssel", "Schlüssel", .noun, .german, "Ich habe meinen Schlüssel im Büro vergessen.", "anahtar", "Kilidi açıp kapamaya yarayan metal araç."), nil, true),
        ]
        var english: [VocabularyEntry] = []
        for (insight, state, favorite) in words {
            guard let entry = try? repository.save(insight, captureSource: .text) else { continue }
            if let state { entry.cardState = state }
            entry.isFavorite = favorite
            if insight.language == .english { english.append(entry) }
        }
        try? repository.context.save()
        seedPodcast(words: english, into: repository, source: source)
        seedPlan(into: repository)
    }

    /// An English quiz every day at 08:00 with five questions on the due words, and an English podcast
    /// on Mondays, Wednesdays and Fridays at 19:30.
    @MainActor
    private static func seedPlan(into repository: WordRepository) {
        let plans = PlanRepository(words: repository)
        let quiz = StudyPlan(activity: .quiz, language: .english, schedule: PlanSchedule(weekdays: PlanSchedule.allWeekdays, hour: 8, minute: 0))
        quiz.id = quizPlanID
        quiz.quizLength = 5
        try? plans.insert(quiz)
        let podcast = StudyPlan(activity: .podcast, language: .english, schedule: PlanSchedule(weekdays: [2, 4, 6], hour: 19, minute: 30))
        podcast.id = podcastPlanID
        try? plans.insert(podcast)
    }

    /// A short English dialogue that uses the sample English words.
    @MainActor
    private static func seedPodcast(words: [VocabularyEntry], into repository: WordRepository, source: InsightSource) {
        let lines: [(PodcastSpeaker, String)] = [
            (.host, "Welcome back! It's raining cats and dogs outside today."),
            (.guest, "I know. I ran from the bus stop to the office."),
            (.host, "Did you bring anything for the meeting?"),
            (.guest, "Yes, I baked cookies for everyone."),
            (.host, "Great. I'm a little nervous about my pitch."),
            (.guest, "Don't worry, your pitch will be fine."),
            (.host, "Thanks! Let's have a cookie first."),
        ]
        let script = PodcastScript(title: "A Rainy Day at the Office", segments: lines.map { PodcastSegment(speaker: $0.0, text: $0.1) })
        _ = try? PodcastRepository(words: repository).save(
            script, words: words, language: .english, nativeLanguage: .turkish, level: .a2, style: .dialogue,
            length: .short, source: source
        )
    }
}
#endif
