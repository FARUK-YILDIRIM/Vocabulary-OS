import Foundation
import VocabularyAI
import VocabularyCore

/// Ten questions of every kind written by the on-device model (SPEC C8, task T24). Targets: every
/// question valid without the local fallback, and the first one ready in under 5 s.
struct QuizEvaluation {
    let client: AppleOnDeviceClient
    /// With no library the model writes every distractor; with one, only cloze sentences.
    let library: [QuizWord]

    static let plan: [QuizPlanItem] = {
        func word(_ term: String, _ lemma: String, _ language: LanguageCode, _ translation: String, _ pos: PartOfSpeech) -> QuizWord {
            QuizWord(id: UUID(), term: term, lemma: lemma, language: language, nativeLanguage: .turkish,
                     translation: translation, meaning: "", partOfSpeech: pos)
        }
        return [
            QuizPlanItem(kind: .meaning, word: word("cookies", "cookie", .english, "çerez", .noun)),
            QuizPlanItem(kind: .reverse, word: word("pitch", "pitch", .english, "sunum", .noun)),
            QuizPlanItem(kind: .cloze, word: word("umbrella", "umbrella", .english, "şemsiye", .noun)),
            QuizPlanItem(kind: .listening, word: word("apple", "apple", .english, "elma", .noun)),
            QuizPlanItem(kind: .cloze, word: word("ran", "run", .english, "yönetmek", .verb)),
            QuizPlanItem(kind: .meaning, word: word("Bank", "Bank", .german, "bank", .noun)),
            QuizPlanItem(kind: .reverse, word: word("Schlüssel", "Schlüssel", .german, "anahtar", .noun)),
            QuizPlanItem(kind: .cloze, word: word("Zug", "Zug", .german, "tren", .noun)),
            QuizPlanItem(kind: .listening, word: word("Tasse", "Tasse", .german, "fincan", .noun)),
            QuizPlanItem(kind: .reverse, word: word("Apfel", "Apfel", .german, "elma", .noun)),
        ]
    }()

    struct Row {
        let item: QuizPlanItem
        let question: QuizQuestion?
        let error: AIError?
        let seconds: Double
    }

    struct Report {
        let rows: [Row]
        var validCount: Int { rows.filter { $0.question != nil }.count }
        var firstSeconds: Double { rows.first?.seconds ?? 0 }
        var medianSeconds: Double {
            let sorted = rows.map(\.seconds).sorted()
            return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        }
        var meetsTargets: Bool { validCount == rows.count && firstSeconds < 5 }

        private func describe(_ row: Row) -> String {
            guard let question = row.question else {
                return "error: \(row.error.map { String(describing: $0) } ?? "")"
            }
            let options = question.options.enumerated().map { index, option in index == question.answerIndex ? "[\(option)]" : option }
            return "\(question.prompt) → \(options.joined(separator: " / "))"
        }

        var summary: String {
            let lines = rows.map { row in
                let mark = row.question == nil ? "-" : "✓"
                let label = "\(row.item.kind.rawValue) \(row.item.word.term)".padding(toLength: 22, withPad: " ", startingAt: 0)
                return "\(mark) \(label) \(String(format: "%4.1fs", row.seconds))  \(describe(row))"
            }
            return (lines + [String(
                format: "valid %d/%d · first question %.2fs · median %.2fs · %@",
                validCount, rows.count, firstSeconds, medianSeconds, meetsTargets ? "targets met" : "targets NOT met"
            )]).joined(separator: "\n")
        }

        var markdown: String {
            let os = ProcessInfo.processInfo.operatingSystemVersionString
            let text = """
            # On-device quiz evaluation

            - Date: \(Date().formatted(date: .abbreviated, time: .shortened))
            - System: macOS \(os), Apple on-device model (one question per call)
            - Command: `swift run --package-path Packages/VocabularyKit vos-eval quiz`
            - Result: valid \(validCount)/\(rows.count) without the local fallback, first question \
            \(String(format: "%.2f", firstSeconds)) s, median \(String(format: "%.2f", medianSeconds)) s \
            (targets: all valid, first question < 5 s — \(meetsTargets ? "met" : "not met"))
            - The right answer always comes from the saved word. Distractors come from the other saved
              words, and the model writes the cloze sentences. Brackets mark the right answer.

            """
            return text + "\n" + table
        }

        /// The questions as a Markdown table.
        var table: String {
            var text = "Valid \(validCount)/\(rows.count).\n\n| Kind | Word | Question | Seconds |\n| --- | --- | --- | --- |\n"
            for row in rows {
                text += "| \(row.item.kind.rawValue) | \(row.item.word.term) (\(row.item.word.language.rawValue)) | \(describe(row)) | \(String(format: "%.1f", row.seconds)) |\n"
            }
            return text
        }
    }

    func run() async -> Report {
        let service = QuizService(client: client, strategy: .stepwise, source: InsightSource(providerID: "apple-on-device"))
        var rows: [Row] = []
        for item in Self.plan {
            let start = ContinuousClock.now
            do {
                let question = try await service.question(item.kind, for: item.word, library: library)
                rows.append(Row(item: item, question: question, error: nil, seconds: seconds(since: start)))
            } catch {
                rows.append(Row(item: item, question: nil, error: error, seconds: seconds(since: start)))
            }
        }
        return Report(rows: rows)
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
