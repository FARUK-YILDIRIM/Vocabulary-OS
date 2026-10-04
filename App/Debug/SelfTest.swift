#if DEBUG
import Foundation
import os
import VocabularyAI
import VocabularyCore
import VocabularySpeech
import VocabularyUI
#if os(macOS)
import AppKit
#endif

/// Debug-only end-to-end checks with the real AI provider and system services (`-vos-self-test
/// capture`, `page`, `object`, `quiz` or `speech`).
///
/// The iOS Simulator has no on-device model assets, so `scripts/mac-smoke.sh --self-test` runs these
/// in the macOS build. Each captures a word, explains it, saves it, logs the outcome and quits. UI
/// tests cover the same flows with canned answers.
enum SelfTest {
    private static let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: "selftest")

    static func runIfRequested(app: AppModel, options: LaunchOptions = LaunchOptions()) async {
        switch options.selfTest {
        case "capture":
            await captureFromText(app: app)
        case "page":
            await captureFromPage(app: app)
        case "object":
            await captureObject(app: app)
        case "quiz":
            await quiz(app: app)
        case "speech":
            await speech(app: app)
        default:
            return
        }
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }

    /// Captures "cookies" from a sentence.
    private static func captureFromText(app: AppModel) async {
        let model = CaptureModel(
            text: "This website uses cookies for tracking.",
            settings: app.settings,
            destination: LibraryCaptureDestination(repository: app.repository),
            insightService: app.makeInsightService
        )
        model.tap(tokenAt: 3)
        model.explain()
        await model.waitForExplanation()
        if let insight = model.insight {
            model.save()
            let saved = (try? app.repository.count(language: insight.language)) ?? 0
            logger.notice("Self-test capture passed: \(insight.term, privacy: .public) → \(insight.translation, privacy: .public) | \(insight.meaning, privacy: .public) | saved=\(saved)")
        } else {
            logFailure("capture", phase: model.phase)
        }
    }

    /// Recognizes the sample page and captures its second "Bank", the one you sit on.
    private static func captureFromPage(app: AppModel) async {
        let page = PageCaptureModel(
            settings: app.settings,
            destination: { [repository = app.repository] photo in
                LibraryCaptureDestination(repository: repository, photo: photo)
            },
            insightService: app.makeInsightService
        )
        await page.load(SamplePage.jpegData())
        guard let word = page.page?.words.last(where: { $0.text == "Bank" }) else {
            logger.error("Self-test page failed: \"Bank\" was not recognized (\(String(describing: page.phase), privacy: .public))")
            return
        }
        page.tap(word)
        guard let model = page.capture else {
            logger.error("Self-test page failed: tapping a word opened no capture")
            return
        }
        model.explain()
        await model.waitForExplanation()
        guard let insight = model.insight else {
            logFailure("page", phase: model.phase)
            return
        }
        model.save()
        let entry = try? app.repository.existingEntry(lemma: insight.lemma, language: insight.language)
        logger.notice("Self-test page passed: \(insight.term, privacy: .public) (\(insight.language.rawValue, privacy: .public)) → \(insight.translation, privacy: .public) | \(model.sentence ?? "", privacy: .public) | photo=\(entry?.imageData != nil)")
    }

    /// Classifies the stand-in cup photo and names it in German.
    private static func captureObject(app: AppModel) async {
        let model = ObjectCaptureModel(
            settings: app.settings,
            destination: { [repository = app.repository] photo in
                LibraryCaptureDestination(repository: repository, photo: photo)
            },
            insightService: app.makeInsightService
        )
        await model.load(SampleObject.jpegData())
        guard model.phase == .choosing, !model.label.isEmpty else {
            logger.error("Self-test object failed: nothing was recognized (\(String(describing: model.phase), privacy: .public))")
            return
        }
        let label = model.label
        model.language = .german
        model.name()
        await model.waitForName()
        guard let insight = model.insight else {
            logger.error("Self-test object failed: \(model.namingError?.localizedDescription ?? "no name", privacy: .public)")
            return
        }
        model.save()
        let entry = try? app.repository.existingEntry(lemma: insight.lemma, language: insight.language)
        logger.notice("Self-test object passed: \(label, privacy: .public) → \(insight.term, privacy: .public) (\(insight.language.rawValue, privacy: .public)) → \(insight.translation, privacy: .public) | \(insight.meaning, privacy: .public) | \(insight.examples.first?.sentence ?? "no example", privacy: .public) | photo=\(entry?.imageData != nil)")
    }

    /// A quiz over the sample words: the first question must be ready in under 5 s (SPEC C8).
    private static func quiz(app: AppModel) async {
        SampleLibrary.seed(into: app.repository)
        let session: QuizSessionModel
        do {
            session = QuizSessionModel(
                language: .english,
                words: try app.quizzes.words(language: .english, source: .all, limit: 10),
                library: try app.quizzes.library(),
                kinds: [.cloze, .meaning, .reverse],
                source: .all,
                service: QuizService(app.makeInsightService()),
                reviews: app.reviews,
                quizzes: app.quizzes
            )
        } catch {
            logger.error("Self-test quiz failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let start = ContinuousClock.now
        await session.start()
        let firstQuestion = ContinuousClock.now - start
        var valid = 0
        var prompts: [String] = []
        while let question = session.current {
            if let word = session.word(for: question), (try? QuizValidator.validate(question, for: word)) != nil {
                valid += 1
            }
            prompts.append("\(question.kind.rawValue): \(question.prompt)")
            session.answer(question.answerIndex)
            await session.next()
        }
        let seconds = Double(firstQuestion.components.seconds) + Double(firstQuestion.components.attoseconds) / 1e18
        let summary = "first question in \(String(format: "%.2f", seconds)) s | \(valid)/\(session.answeredCount) valid | \(prompts.joined(separator: " · "))"
        if session.answeredCount > 0, valid == session.answeredCount, seconds < 5 {
            logger.notice("Self-test quiz passed: \(summary, privacy: .public)")
        } else {
            logger.error("Self-test quiz failed: \(summary, privacy: .public)")
        }
    }

    /// Says a German word with the system synthesizer and waits for it to finish.
    private static func speech(app: AppModel) async {
        guard let voice = VoiceCatalog.installed().bestVoice(for: .german) else {
            logger.error("Self-test speech failed: no German voice is installed")
            return
        }
        let start = ContinuousClock.now
        app.speech.speak("Die Tasse", language: .german)
        while app.speech.state != .idle, ContinuousClock.now - start < .seconds(10) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let elapsed = ContinuousClock.now - start
        if app.speech.state == .idle {
            logger.notice("Self-test speech passed: “Die Tasse” spoken by \(voice.name, privacy: .public) (\(voice.language, privacy: .public)) in \(elapsed.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2))), privacy: .public)")
        } else {
            logger.error("Self-test speech failed: the synthesizer didn't finish within 10 s")
        }
    }

    private static func logFailure(_ test: String, phase: CaptureModel.Phase) {
        if case .failed(let error) = phase {
            logger.error("Self-test \(test, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.error("Self-test \(test, privacy: .public) failed: no insight")
        }
    }
}
#endif
