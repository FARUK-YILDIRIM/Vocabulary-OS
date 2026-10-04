#if DEBUG
import Foundation
import VocabularyCore
import VocabularyData

/// Sample words and a podcast episode for UI tests and screenshots (`-vos-seed-library YES`, Debug
/// builds only).
enum SampleLibrary {
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
