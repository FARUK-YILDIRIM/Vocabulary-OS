import Foundation
import VocabularyAI
import VocabularyCore

/// Evaluates prompts against Apple's on-device model on this Mac (ADR-003, task T09).
///
///     swift run --package-path Packages/VocabularyKit vos-eval insight [--report <file.md>]
@main
struct VosEval {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "insight" else {
            print("usage: vos-eval insight [--report <file.md>]")
            exit(64)
        }
        let client = AppleOnDeviceClient()
        guard client.availability == .available else {
            print("The on-device model is not available here: \(client.availability)")
            exit(1)
        }
        let report = await InsightEvaluation(client: client).run()
        print(report.summary)
        if let index = arguments.firstIndex(of: "--report"), arguments.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: arguments[index + 1])
            do {
                try report.markdown.write(to: url, atomically: true, encoding: .utf8)
                print("Report written to \(url.path)")
            } catch {
                print("Could not write the report: \(error.localizedDescription)")
                exit(1)
            }
        }
        exit(report.meetsTargets ? 0 : 2)
    }
}

struct InsightEvaluation {
    let client: AppleOnDeviceClient

    struct Row {
        let fixture: InsightFixture
        let insight: WordInsight?
        let error: AIError?
        let seconds: Double
        var senseOK: Bool {
            guard let insight else { return false }
            let text = [insight.englishGloss ?? "", insight.translation].joined(separator: " ").lowercased()
            return fixture.senseKeywords.contains { text.contains($0) }
        }
        var translationOK: Bool {
            guard let translation = insight?.translation.lowercased() else { return false }
            return fixture.translationKeywords.contains { translation.contains($0) }
        }
    }

    struct Report {
        let rows: [Row]
        var senseCount: Int { rows.filter(\.senseOK).count }
        var translationCount: Int { rows.filter(\.translationOK).count }
        var validCount: Int { rows.filter { $0.insight != nil }.count }
        var medianSeconds: Double {
            let sorted = rows.map(\.seconds).sorted()
            return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        }
        /// SPEC C3: at least 8 of 10 right senses, every answer valid, median under 3 s.
        var meetsTargets: Bool {
            senseCount * 10 >= rows.count * 8 && validCount == rows.count && medianSeconds < 3
        }

        var summary: String {
            let lines = rows.map { row in
                let mark = (row.senseOK ? "S" : "-") + (row.translationOK ? "T" : "-")
                let detail = row.insight.map { "\($0.translation) | \($0.meaning) | gloss: \($0.englishGloss ?? "")" }
                    ?? "error: \(row.error.map { String(describing: $0) } ?? "")"
                let term = row.fixture.term.padding(toLength: 22, withPad: " ", startingAt: 0)
                return "\(mark) \(term) \(String(format: "%4.1fs", row.seconds))  \(detail)"
            }
            return (lines + [String(
                format: "right sense %d/%d · right translation %d/%d · valid %d/%d · median %.2fs · %@",
                senseCount, rows.count, translationCount, rows.count, validCount, rows.count, medianSeconds,
                meetsTargets ? "targets met" : "targets NOT met"
            )]).joined(separator: "\n")
        }

        var markdown: String {
            let os = ProcessInfo.processInfo.operatingSystemVersionString
            var text = """
            # On-device insight evaluation

            - Date: \(Date().formatted(date: .abbreviated, time: .shortened))
            - System: macOS \(os), Apple on-device model (stepwise strategy)
            - Command: `swift run --package-path Packages/VocabularyKit vos-eval insight`
            - Result: right sense \(senseCount)/\(rows.count), right translation \(translationCount)/\(rows.count), \
            valid \(validCount)/\(rows.count), median latency \(String(format: "%.2f", medianSeconds)) s \
            (targets: ≥ 8/10 senses, all valid, median < 3 s — \(meetsTargets ? "met" : "not met"))

            | Term | Sentence | Sense | Translation | Native entry | Seconds |
            | --- | --- | --- | --- | --- | --- |

            """
            for row in rows {
                let entry = row.insight.map { "\($0.translation) — \($0.meaning)" } ?? "error"
                text += "| \(row.fixture.term) | \(row.fixture.sentence) | \(row.senseOK ? "✓" : "✗") \(row.insight?.englishGloss ?? "") | "
                text += "\(row.translationOK ? "✓" : "✗") | \(entry) | \(String(format: "%.1f", row.seconds)) |\n"
            }
            return text
        }
    }

    func run() async -> Report {
        let service = InsightService(client: client, strategy: .stepwise, source: InsightSource(providerID: "apple-on-device"))
        var rows: [Row] = []
        for fixture in insightFixtures {
            let request = InsightRequest(term: fixture.term, sentence: fixture.sentence, language: fixture.language, nativeLanguage: fixture.native)
            let start = ContinuousClock.now
            do {
                let insight = try await service.insight(for: request)
                rows.append(Row(fixture: fixture, insight: insight, error: nil, seconds: seconds(since: start)))
            } catch {
                rows.append(Row(fixture: fixture, insight: nil, error: error, seconds: seconds(since: start)))
            }
        }
        return Report(rows: rows)
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
