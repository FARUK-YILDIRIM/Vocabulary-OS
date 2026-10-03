import VocabularyCore

/// A sentence whose term has a known right sense. Keywords are matched case-insensitively.
struct InsightFixture: Sendable {
    let term: String
    let sentence: String
    let language: LanguageCode
    let native: LanguageCode
    /// Words that appear in a correct English gloss of the sense.
    let senseKeywords: [String]
    /// Words that appear in a correct native-language translation.
    let translationKeywords: [String]
}

/// Pairs of sentences where the same word has different senses, plus idioms and inflected forms.
/// Keep these out of the prompts' few-shot examples so the evaluation stays honest.
let insightFixtures: [InsightFixture] = [
    .init(term: "cookies", sentence: "This website uses cookies for tracking.", language: .english, native: .turkish,
          senseKeywords: ["file", "data", "track"], translationKeywords: ["çerez"]),
    .init(term: "cookie", sentence: "She dipped a chocolate chip cookie in her milk.", language: .english, native: .turkish,
          senseKeywords: ["biscuit", "baked", "sweet", "cookie"], translationKeywords: ["kurabiye", "bisküvi"]),
    .init(term: "Bank", sentence: "Wir saßen auf einer Bank im Park.", language: .german, native: .turkish,
          senseKeywords: ["bench", "seat"], translationKeywords: ["bank", "oturak"]),
    .init(term: "Bank", sentence: "Ich muss zur Bank, um Geld abzuheben.", language: .german, native: .turkish,
          senseKeywords: ["bank", "financ"], translationKeywords: ["banka"]),
    .init(term: "pitch", sentence: "She gave a great pitch to the investors.", language: .english, native: .turkish,
          senseKeywords: ["present", "speech", "proposal", "talk", "persua"], translationKeywords: ["sunum", "teklif", "tanıtım"]),
    .init(term: "pitch", sentence: "The football pitch was wet after the rain.", language: .english, native: .turkish,
          senseKeywords: ["field", "ground", "area"], translationKeywords: ["saha"]),
    .init(term: "ran", sentence: "He ran the family company for ten years.", language: .english, native: .turkish,
          senseKeywords: ["manage", "operate", "lead", "direct", "charge"], translationKeywords: ["yönet", "işlet"]),
    .init(term: "raining cats and dogs", sentence: "Take an umbrella, it's raining cats and dogs.", language: .english, native: .turkish,
          senseKeywords: ["heav", "pour", "hard"], translationKeywords: ["bardaktan", "şiddetli", "sağanak", "yoğun"]),
    .init(term: "abzuheben", sentence: "Ich muss zur Bank, um Geld abzuheben.", language: .german, native: .english,
          senseKeywords: ["withdraw", "take out"], translationKeywords: ["withdraw", "take out"]),
    .init(term: "Schlüssel", sentence: "Ich habe meinen Schlüssel im Büro vergessen.", language: .german, native: .turkish,
          senseKeywords: ["key", "lock"], translationKeywords: ["anahtar"]),
]
