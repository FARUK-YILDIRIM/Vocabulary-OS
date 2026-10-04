#if DEBUG
import Foundation
import os
import VocabularyCore
import VocabularyUI
#if os(macOS)
import AppKit
#endif

/// Debug-only end-to-end checks with the real AI provider (`-vos-self-test capture` or `page`).
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

    private static func logFailure(_ test: String, phase: CaptureModel.Phase) {
        if case .failed(let error) = phase {
            logger.error("Self-test \(test, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.error("Self-test \(test, privacy: .public) failed: no insight")
        }
    }
}
#endif
