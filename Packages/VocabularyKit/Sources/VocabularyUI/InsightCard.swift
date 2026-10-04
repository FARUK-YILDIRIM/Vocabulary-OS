import SwiftUI
import VocabularyCore

/// A word's meaning in context, shown after capture and on the word's detail page (SPEC C3, C4).
public struct InsightCard: View {
    private let insight: WordInsight
    private let providerName: String?
    private let onListen: (() -> Void)?

    /// - Parameter onListen: shows a button next to the word that says it.
    public init(insight: WordInsight, providerName: String? = nil, onListen: (() -> Void)? = nil) {
        self.insight = insight
        self.providerName = providerName
        self.onListen = onListen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: insight.term).font(.title2.bold())
                    if let details = headwordDetails {
                        Text(verbatim: details).foregroundStyle(.secondary)
                    }
                    if let onListen {
                        Button(action: onListen) {
                            Label {
                                Text("Listen", bundle: .module)
                            } icon: {
                                Image(systemName: "speaker.wave.2")
                            }
                            .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("insight-listen")
                    }
                }
                Text(verbatim: insight.translation)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("insight-translation")
            }

            Text(verbatim: insight.meaning)
                .accessibilityIdentifier("insight-meaning")

            if let context = insight.context {
                HighlightedSentence(sentence: context, term: insight.term)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }

            if let grammarNote = insight.grammarNote {
                Label {
                    Text(verbatim: grammarNote)
                } icon: {
                    Image(systemName: "text.book.closed")
                }
                .font(.callout)
            }

            if !insight.examples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples", bundle: .module).font(.headline)
                    ForEach(insight.examples, id: \.self) { example in
                        VStack(alignment: .leading, spacing: 2) {
                            HighlightedSentence(sentence: example.sentence, term: insight.lemma)
                            Text(verbatim: example.translation).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !insight.otherMeanings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Other meanings", bundle: .module).font(.headline)
                    Text(verbatim: insight.otherMeanings.joined(separator: " · ")).foregroundStyle(.secondary)
                }
            }

            if let providerName {
                Text("Explained by \(providerName)", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headwordDetails: String? {
        let parts = [
            insight.lemma.matchingKey == insight.term.matchingKey ? nil : insight.lemma,
            insight.partOfSpeech.map(\.localizedName),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A sentence with the term emphasized, matched case- and diacritic-insensitively.
public struct HighlightedSentence: View {
    let sentence: String
    let term: String

    public init(sentence: String, term: String) {
        self.sentence = sentence
        self.term = term
    }

    public var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var text = AttributedString(sentence)
        if !term.isEmpty, let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].font = .body.bold()
            text[range].foregroundColor = .primary
        }
        return text
    }
}

extension PartOfSpeech {
    var localizedName: String {
        switch self {
        case .noun: String(localized: "noun", bundle: .module)
        case .verb: String(localized: "verb", bundle: .module)
        case .adjective: String(localized: "adjective", bundle: .module)
        case .adverb: String(localized: "adverb", bundle: .module)
        case .pronoun: String(localized: "pronoun", bundle: .module)
        case .preposition: String(localized: "preposition", bundle: .module)
        case .conjunction: String(localized: "conjunction", bundle: .module)
        case .interjection: String(localized: "interjection", bundle: .module)
        case .determiner: String(localized: "determiner", bundle: .module)
        case .number: String(localized: "number", bundle: .module)
        case .phrase: String(localized: "phrase", bundle: .module)
        case .other: String(localized: "word", bundle: .module)
        }
    }
}

#Preview {
    InsightCard(
        insight: WordInsight(
            term: "cookies", lemma: "cookie", partOfSpeech: .noun, language: .english, nativeLanguage: .turkish,
            context: "This website uses cookies for tracking.", translation: "çerez",
            meaning: "Web sitelerinin tarayıcıda sakladığı küçük veri dosyası.",
            examples: [UsageExample(sentence: "Accept the cookies to continue.", translation: "Devam etmek için çerezleri kabul edin.")],
            source: InsightSource(providerID: "apple-on-device")
        ),
        providerName: "Apple on-device model"
    )
    .padding()
}
