#if DEBUG
import Foundation
import VocabularyCore
import VocabularyData

/// Sample words for UI tests and screenshots (`-vos-seed-library YES`, Debug builds only).
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
        for (insight, state, favorite) in words {
            guard let entry = try? repository.save(insight, captureSource: .text) else { continue }
            if let state { entry.cardState = state }
            entry.isFavorite = favorite
        }
        try? repository.context.save()
    }
}
#endif
