import XCTest

/// Capture → Page: tap a word on a photographed page and save it with its sentence (task T20).
@MainActor
final class PageCaptureUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Uses a generated page and canned AI answers: the Simulator has no camera, photos or model.
    func testTappingAWordOnAPageCapturesItWithItsSentence() {
        let app = launch(extraArguments: ["-vos-sample-page", "YES", "-vos-ai-stub", "YES"])

        let banks = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-word-' AND label == 'Bank'"))
        XCTAssertTrue(banks.firstMatch.waitForExistence(timeout: 20), "The page's words should be recognized")
        XCTAssertEqual(banks.count, 2)
        attachScreenshot(of: app, named: "01-page")

        banks.element(boundBy: 1).tap()
        let term = app.staticTexts["capture-term"]
        XCTAssertTrue(term.waitForExistence(timeout: 5))
        XCTAssertEqual(term.label, "Bank")
        XCTAssertTrue(app.buttons["language-chip-de"].isSelected, "German should be detected from the sentence")
        XCTAssertTrue(app.staticTexts["alten"].exists, "The whole sentence, which wraps on the page, is the context")

        app.buttons["capture-explain"].tap()
        XCTAssertTrue(app.buttons["capture-save"].waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "02-explained")
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-saved"].waitForExistence(timeout: 5))
        app.buttons["page-capture-done"].tap()

        app.buttons["Library"].firstMatch.tap()
        app.buttons["German"].tap()
        let row = app.descendants(matching: .any)["library-row-Bank"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.images["Captured photo"].waitForExistence(timeout: 5), "The page photo is saved with the word")
        attachScreenshot(of: app, named: "03-saved-with-photo")
    }

    func testAnEmptyPageOffersPhotoSources() {
        let app = launch(extraArguments: [])

        XCTAssertTrue(app.buttons["photo-choose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["photo-choose-file"].exists)
        attachScreenshot(of: app, named: "04-empty")
    }

    private func launch(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-tab", "capture",
            "-vos-capture-mode", "page", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + extraArguments
        app.launch()
        return app
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
