import XCTest

/// A quiz over the sample words, from setup to the summary (task T25).
@MainActor
final class QuizUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Canned AI answers: the Simulator has no on-device model, so cloze questions come from the
    /// saved sentences.
    func testTakingAQuizOnDueWords() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-seed-library", "YES", "-vos-ai-stub", "YES",
            "-vos-tab", "practice", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        let start = app.buttons["quiz-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        // English has three words due: one due for review and two new ones.
        XCTAssertTrue(app.staticTexts["3 questions from your words. Every answer counts as a review."].exists)
        attachScreenshot(of: app, named: "01-setup")
        start.tap()

        var answered = 0
        while answered < 3 {
            let option = app.buttons["quiz-option-0"]
            XCTAssertTrue(option.waitForExistence(timeout: 10), "Question \(answered + 1) should appear")
            // A listening question plays the word instead of showing it.
            let listen = app.buttons["quiz-listen"]
            XCTAssertTrue(listen.exists || app.staticTexts["quiz-prompt"].exists)
            if listen.exists {
                attachScreenshot(of: app, named: "listening-question")
            }
            if answered == 0 {
                attachScreenshot(of: app, named: "02-question")
            }
            option.tap()
            XCTAssertTrue(app.descendants(matching: .any)["quiz-feedback"].waitForExistence(timeout: 5))
            if answered == 0 {
                attachScreenshot(of: app, named: "03-feedback")
            }
            app.buttons["quiz-next"].tap()
            answered += 1
        }

        let score = app.staticTexts["quiz-score"]
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        XCTAssertTrue(score.label.hasSuffix("of 3 right"))
        attachScreenshot(of: app, named: "04-summary")
        app.buttons["quiz-done"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
