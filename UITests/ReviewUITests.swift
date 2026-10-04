import XCTest

/// Today counts and a flashcard session (task T23).
@MainActor
final class ReviewUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testReviewingTodaysEnglishWords() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-seed-library", "YES",
            "-vos-tab", "today", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        let english = app.staticTexts["today-counts-en"]
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertEqual(english.label, "1 due · 2 new")
        XCTAssertEqual(app.staticTexts["today-counts-de"].label, "0 due · 2 new")
        attachScreenshot(of: app, named: "01-today")

        app.buttons["today-review-en"].tap()
        // The due word first, then new words in the order they were captured.
        answer("pitch", .good, in: app, screenshot: "02-revealed")
        answer("cookies", .again, in: app)
        answer("raining cats and dogs", .good, in: app)
        // The word answered Again comes back before the session ends.
        answer("cookies", .good, in: app)

        XCTAssertTrue(app.buttons["flashcard-done"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "03-complete")
        app.buttons["flashcard-done"].tap()

        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertEqual(english.label, "All done for today")
    }

    private func answer(_ term: String, _ rating: String, in app: XCUIApplication, screenshot: String? = nil) {
        let shownTerm = app.staticTexts["flashcard-term"]
        XCTAssertTrue(shownTerm.waitForExistence(timeout: 5))
        XCTAssertEqual(shownTerm.label, term)
        app.buttons["flashcard-show-answer"].tap()
        XCTAssertTrue(app.staticTexts["flashcard-translation"].waitForExistence(timeout: 5))
        if let screenshot {
            attachScreenshot(of: app, named: screenshot)
        }
        app.buttons["flashcard-rate-\(rating)"].tap()
    }

    private func answer(_ term: String, _ rating: Rating, in app: XCUIApplication, screenshot: String? = nil) {
        answer(term, rating.rawValue, in: app, screenshot: screenshot)
    }

    private enum Rating: String {
        case again, hard, good, easy
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
