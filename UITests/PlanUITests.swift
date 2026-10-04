import XCTest

/// Study plans: editing them, and reminders and links that start their activity (task T29).
@MainActor
final class PlanUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let quizPlanLink = "vocabularyos://plan/5A3F1E2D-7C4B-4E8A-9F60-1B2C3D4E5F60"
    private let podcastPlanLink = "vocabularyos://plan/5A3F1E2D-7C4B-4E8A-9F60-1B2C3D4E5F61"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// The sample library includes an English quiz plan, every day at 08:00, and an English podcast
    /// plan on Mondays, Wednesdays and Fridays at 19:30.
    private func launch(tab: String, _ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-seed-library", "YES", "-vos-ai-stub", "YES",
            "-vos-tab", tab, "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + arguments
        app.launch()
        return app
    }

    /// The system asks once per install whether the app may send notifications.
    private func allowNotificationsIfAsked() {
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }
    }

    private func planRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'plan-row' AND label BEGINSWITH %@", title)).firstMatch
    }

    /// The label with plain spaces: times put a narrow no-break space before "AM" and "PM".
    private func text(of element: XCUIElement) -> String {
        element.label.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    func testCreatingEditingAndDeletingAPlan() {
        let app = launch(tab: "practice")
        let newPlan = app.buttons["practice-new-plan"]
        // Plans come after the quiz and podcasts, below the fold on an iPhone.
        for _ in 0..<3 where !newPlan.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(newPlan.waitForExistence(timeout: 5))
        let quiz = planRow("Quiz · English", in: app)
        XCTAssertTrue(text(of: quiz).hasSuffix("Every day at 8:00 AM"), quiz.label)
        XCTAssertTrue(text(of: planRow("Podcast · English", in: app)).hasSuffix("Mon, Wed, Fri at 7:30 PM"))
        attachScreenshot(of: app, named: "01-plans")

        // German reviews on Mondays, Wednesdays and Fridays at 08:00.
        newPlan.tap()
        app.buttons["Review"].tap()
        app.buttons["plan-language"].tap()
        app.buttons["German"].tap()
        for day in [1, 3, 5, 7] {
            app.buttons["plan-day-\(day)"].tap()
        }
        attachScreenshot(of: app, named: "02-editor")
        app.buttons["plan-save"].tap()
        allowNotificationsIfAsked()
        let review = planRow("Review · German", in: app)
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(text(of: review).hasSuffix("Mon, Wed, Fri at 8:00 AM"), review.label)

        // Turned off, it keeps its days.
        review.tap()
        let enabled = app.switches["plan-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.buttons["plan-save"].tap()
        expectation(for: NSPredicate(format: "label ENDSWITH %@", "AM · Off"), evaluatedWith: review)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(text(of: review).hasSuffix("Mon, Wed, Fri at 8:00 AM · Off"), review.label)

        // Deleted, it's gone.
        review.tap()
        let delete = app.buttons["plan-delete"]
        for _ in 0..<3 where !delete.isHittable {
            app.swipeUp()
        }
        delete.tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 5))
        XCTAssertTrue(quiz.exists)
    }

    func testTappingAReminderStartsItsQuiz() {
        let app = launch(tab: "today", ["-vos-remind-in", "4"])
        allowNotificationsIfAsked()
        let reminder = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Quiz · English")).firstMatch
        XCTAssertTrue(reminder.waitForExistence(timeout: 30), "The plan's reminder should arrive")
        XCTAssertTrue(reminder.label.contains("Tap to start: 5 questions on your words."), reminder.label)
        attachScreenshot(of: springboard, named: "03-reminder")
        reminder.tap()
        XCTAssertTrue(app.buttons["quiz-option-0"].waitForExistence(timeout: 10), "Tapping the reminder starts the quiz")
        attachScreenshot(of: app, named: "04-quiz")
    }

    func testPlanLinksStartTheirActivity() throws {
        let app = launch(tab: "library")
        app.open(try XCTUnwrap(URL(string: quizPlanLink)))
        let option = app.buttons["quiz-option-0"]
        XCTAssertTrue(option.waitForExistence(timeout: 10), "The quiz plan's link starts the quiz")
        app.buttons["quiz-close"].tap()
        XCTAssertTrue(option.waitForNonExistence(timeout: 5))

        // A podcast plan writes its episode at once and opens it.
        app.open(try XCTUnwrap(URL(string: podcastPlanLink)))
        let title = app.staticTexts["podcast-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "The podcast plan's link writes an episode")
        XCTAssertEqual(title.label, "A Day in Town")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
