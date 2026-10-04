import SwiftUI
import VocabularyCore
import VocabularyData
import VocabularyUI

/// A flashcard session: the word in its sentence, then its meaning and four ratings (SPEC C7,
/// ADR-007). On a Mac, Space shows the answer and 1–4 rate it.
struct FlashcardSessionView: View {
    let model: ReviewSessionModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let entry = model.current {
                    card(for: entry)
                } else {
                    summary
                }
            }
            .navigationTitle(Text(verbatim: model.language.localizedName()))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: close)
                        .accessibilityIdentifier("flashcard-close")
                }
                if !model.isFinished {
                    ToolbarItem(placement: .primaryAction) {
                        Text("\(model.finished) of \(model.total)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("flashcard-progress")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    // MARK: Card

    private func card(for entry: VocabularyEntry) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Text(verbatim: entry.term)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("flashcard-term")
                    if let context = entry.context {
                        HighlightedSentence(sentence: context, term: entry.term)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                    }
                    if let imageData = entry.imageData, let image = Image(imageData: imageData) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(.rect(cornerRadius: 10))
                            .accessibilityLabel(Text("Captured photo"))
                    }
                    if model.isRevealed {
                        Divider()
                        answer(for: entry)
                    }
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            Divider()
            controls
                .padding()
                .frame(maxWidth: 640)
            if let message = model.errorMessage {
                Text(verbatim: message).font(.callout).foregroundStyle(.red).padding(.bottom)
            }
        }
        .id(entry.id)
    }

    private func answer(for entry: VocabularyEntry) -> some View {
        let insight = entry.insight
        return VStack(spacing: 12) {
            Text(verbatim: insight.translation)
                .font(.title.bold())
                .foregroundStyle(.tint)
                .accessibilityIdentifier("flashcard-translation")
            Text(verbatim: insight.meaning)
                .font(.body)
            ForEach(insight.examples.prefix(2), id: \.self) { example in
                VStack(spacing: 2) {
                    HighlightedSentence(sentence: example.sentence, term: insight.term)
                    Text(verbatim: example.translation).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var controls: some View {
        if model.isRevealed {
            HStack(spacing: 8) {
                ForEach(Array(ReviewRating.allCases.enumerated()), id: \.element) { index, rating in
                    ratingButton(rating, shortcut: KeyEquivalent(Character(String(index + 1))))
                }
            }
        } else {
            Button {
                model.reveal()
            } label: {
                Text("Show Answer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityIdentifier("flashcard-show-answer")
        }
    }

    private func ratingButton(_ rating: ReviewRating, shortcut: KeyEquivalent) -> some View {
        Button {
            model.rate(rating)
        } label: {
            VStack(spacing: 2) {
                Text(rating.title).fontWeight(.semibold)
                // The interval this answer gives; nothing for a word already rescheduled today.
                if let days = model.intervalPreview(for: rating) {
                    Text("^[\(days) day](inflect: true)").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(rating.tint)
        .keyboardShortcut(shortcut, modifiers: [])
        .accessibilityIdentifier("flashcard-rate-\(rating.rawValue)")
    }

    // MARK: Summary

    private var summary: some View {
        ContentUnavailableView {
            Label("Session Complete", systemImage: "checkmark.circle")
        } description: {
            Text("You reviewed ^[\(model.finished) word](inflect: true).")
        } actions: {
            Button("Done", action: close)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("flashcard-done")
        }
    }
}

extension ReviewRating {
    var title: LocalizedStringKey {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    var tint: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}
