import Foundation
import VocabularyAI
import VocabularyCore

/// Two-minute podcast scripts written by the on-device model (SPEC C9, task T27). Target: every
/// script valid, with every chosen word used.
struct PodcastEvaluation {
    let client: any GenerationClient

    static let requests: [PodcastRequest] = {
        func words(_ terms: [(String, String)], _ language: LanguageCode) -> [QuizWord] {
            terms.map { QuizWord(id: UUID(), term: $0.0, lemma: $0.1, language: language, nativeLanguage: .turkish, translation: "", meaning: "") }
        }
        return [
            PodcastRequest(
                words: words([("cookies", "cookie"), ("pitch", "pitch"), ("umbrella", "umbrella"), ("ran", "run"), ("train", "train")], .english),
                language: .english, nativeLanguage: .turkish, level: .b1, length: .short, style: .dialogue
            ),
            PodcastRequest(
                words: words([("Bank", "Bank"), ("Schlüssel", "Schlüssel"), ("Zug", "Zug"), ("Tasse", "Tasse"), ("Apfel", "Apfel")], .german),
                language: .german, nativeLanguage: .turkish, level: .a2, length: .short, style: .dialogue
            ),
            PodcastRequest(
                words: words([("Bank", "Bank"), ("Schlüssel", "Schlüssel"), ("Zug", "Zug")], .german),
                language: .german, nativeLanguage: .turkish, level: .a2, length: .short, style: .story
            ),
        ]
    }()

    struct Row {
        let request: PodcastRequest
        let script: PodcastScript?
        let error: AIError?
        let seconds: Double
    }

    struct Report {
        let rows: [Row]
        var validCount: Int { rows.filter { $0.script != nil }.count }
        var meetsTargets: Bool { validCount == rows.count }

        private func label(_ request: PodcastRequest) -> String {
            "\(request.language.rawValue) \(request.style.rawValue) \(request.level.label)"
        }

        var summary: String {
            var lines: [String] = []
            for row in rows {
                if let script = row.script {
                    lines.append("✓ \(label(row.request))  \(String(format: "%.1fs", row.seconds))  «\(script.title)», \(script.segments.count) segments, \(script.wordCount) words")
                    for segment in script.segments {
                        lines.append("    \(segment.speaker.rawValue): \(segment.text)")
                    }
                } else {
                    lines.append("- \(label(row.request))  \(String(format: "%.1fs", row.seconds))  error: \(row.error.map { String(describing: $0) } ?? "")")
                }
            }
            lines.append("valid \(validCount)/\(rows.count) · \(meetsTargets ? "targets met" : "targets NOT met")")
            return lines.joined(separator: "\n")
        }

        var markdown: String {
            let os = ProcessInfo.processInfo.operatingSystemVersionString
            var text = """
            # On-device podcast evaluation

            - Date: \(Date().formatted(date: .abbreviated, time: .shortened))
            - System: macOS \(os), Apple on-device model (drafted in short parts, then a line for each word the draft left out)
            - Command: `swift run --package-path Packages/VocabularyKit vos-eval podcast`
            - Result: valid \(validCount)/\(rows.count), every chosen word used in each valid script \
            (target: all valid — \(meetsTargets ? "met" : "not met"))

            """
            for row in rows {
                text += "\n## \(label(row.request)): \(row.request.words.map(\.term).joined(separator: ", "))\n\n"
                if let script = row.script {
                    text += "«\(script.title)» — \(script.segments.count) segments, \(script.wordCount) words, \(String(format: "%.1f", row.seconds)) s\n\n"
                    for segment in script.segments {
                        text += "- **\(segment.speaker.rawValue)**: \(segment.text)\n"
                    }
                } else {
                    text += "Error: \(row.error.map { String(describing: $0) } ?? "")\n"
                }
            }
            return text
        }
    }

    func run() async -> Report {
        let service = PodcastService(client: client, strategy: .stepwise, source: InsightSource(providerID: "apple-on-device"))
        var rows: [Row] = []
        for request in Self.requests {
            let start = ContinuousClock.now
            do {
                let script = try await service.script(for: request)
                rows.append(Row(request: request, script: script, error: nil, seconds: seconds(since: start)))
            } catch {
                rows.append(Row(request: request, script: nil, error: error, seconds: seconds(since: start)))
            }
        }
        return Report(rows: rows)
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
