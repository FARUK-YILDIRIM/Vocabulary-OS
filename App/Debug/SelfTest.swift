#if DEBUG
import Foundation
import os
import VocabularyCore
import VocabularyUI
#if os(macOS)
import AppKit
#endif

/// Debug-only end-to-end check with the real AI provider (`-vos-self-test capture`).
///
/// The iOS Simulator has no on-device model assets, so `scripts/mac-smoke.sh --self-test` runs this
/// in the macOS build: it captures "cookies" from a sentence, explains it, saves it, logs the outcome
/// and quits. UI tests cover the same flow with canned answers.
enum SelfTest {
    private static let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: "selftest")

    static func runIfRequested(app: AppModel, options: LaunchOptions = LaunchOptions()) async {
        guard options.selfTest == "capture" else { return }
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
        } else if case .failed(let error) = model.phase {
            logger.error("Self-test capture failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.error("Self-test capture failed: no insight")
        }
        #if os(macOS)
        NSApp.terminate(nil)
        #endif
    }
}
#endif
