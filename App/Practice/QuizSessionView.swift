import SwiftUI
import VocabularyCore
import VocabularyUI

/// A quiz: one question at a time, immediate feedback, and a summary of what to repeat (SPEC C8).
/// On a Mac, 1–4 pick an answer and Return goes on.
struct QuizSessionView: View {
    @Environment(AppModel.self) private var app
    let model: QuizSessionModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: model.language.localizedName()))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: close)
                            .accessibilityIdentifier("quiz-close")
                    }
                    if model.phase != .finished {
                        ToolbarItem(placement: .primaryAction) {
                            Text("\(min(model.answeredCount + 1, model.total)) of \(model.total)")
                                .monospacedDigit()
                                .accessibilityIdentifier("quiz-progress")
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
        .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .preparing:
            ProgressView("Writing questions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("quiz-preparing")
        case .asking, .answered:
            if let question = model.current {
                questionView(question)
            }
        case .finished:
            summary
        }
    }

    // MARK: Question

    private func questionView(_ question: QuizQuestion) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Text(question.kind.instruction)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if question.kind == .listening && model.phase == .asking {
                        // The word is heard, not read, until the learner answers.
                        Button {
                            listen(to: question)
                        } label: {
                            Label("Play Again", systemImage: "speaker.wave.2.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("quiz-listen")
                    } else {
                        Text(verbatim: question.prompt)
                            .font(question.kind == .cloze ? .title2 : .largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("quiz-prompt")
                    }
                    VStack(spacing: 10) {
                        ForEach(question.options.indices, id: \.self) { index in
                            optionButton(question, index: index)
                        }
                    }
                    if case .answered(let correct) = model.phase {
                        feedback(question, correct: correct)
                    }
                    if let message = model.errorMessage {
                        Text(verbatim: message).font(.callout).foregroundStyle(.red)
                    }
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            if case .answered = model.phase {
                Divider()
                Button {
                    Task { await model.next() }
                } label: {
                    Text(model.answeredCount < model.total ? "Next" : "See Results").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
                .padding()
                .frame(maxWidth: 640)
                .accessibilityIdentifier("quiz-next")
            }
        }
        .id(question.id)
        .task(id: question.id) {
            if question.kind == .listening {
                listen(to: question)
            }
        }
    }

    private func listen(to question: QuizQuestion) {
        app.speech.speak(question.prompt, language: model.language)
    }

    private func optionButton(_ question: QuizQuestion, index: Int) -> some View {
        let isAnswered = model.phase != .asking
        let isRight = index == question.answerIndex
        let isChosen = index == model.selectedOption
        return Button {
            model.answer(index)
        } label: {
            HStack {
                Text(verbatim: question.options[index])
                Spacer(minLength: 8)
                if isAnswered && isRight {
                    Image(systemName: "checkmark.circle.fill")
                } else if isAnswered && isChosen {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(isAnswered ? (isRight ? .green : (isChosen ? .red : .secondary)) : .accentColor)
        .disabled(isAnswered && !isRight && !isChosen)
        .allowsHitTesting(!isAnswered)
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
        .accessibilityIdentifier("quiz-option-\(index)")
    }

    private func feedback(_ question: QuizQuestion, correct: Bool) -> some View {
        VStack(spacing: 6) {
            if correct {
                Label("Right", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("The answer is “\(question.correctAnswer)”.", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }
            if let word = model.word(for: question) {
                Text(verbatim: "\(word.term) — \(word.translation)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.headline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quiz-feedback")
    }

    // MARK: Summary

    private var summary: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("\(model.correctCount) of \(model.answeredCount) right")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("quiz-score")
                if !model.missed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Repeat these").font(.headline)
                        ForEach(model.missed) { word in
                            Text(verbatim: "\(word.term) — \(word.translation)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                }
                Button("Done", action: close)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("quiz-done")
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }
}

extension QuizKind {
    var instruction: LocalizedStringKey {
        switch self {
        case .meaning: "What does it mean?"
        case .reverse: "Which word is it?"
        case .cloze: "Which word fills the gap?"
        case .listening: "What did you hear?"
        }
    }
}
