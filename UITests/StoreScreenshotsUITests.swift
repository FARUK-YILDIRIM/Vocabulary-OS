import XCTest

/// The App Store screenshots: the sample library of a Turkish speaker learning English and German.
/// Runs only from `scripts/store-screenshots.sh`, which sets a clean status bar and collects the
/// images; the test names keep the screens in order.
@MainActor
final class StoreScreenshotsUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VOS_STORE_SCREENSHOTS"] == "1",
            "scripts/store-screenshots.sh makes the App Store screenshots"
        )
    }

    func test1Today() {
        let app = launch(tab: "today")
        XCTAssertTrue(app.descendants(matching: .any)["today-counts-en"].waitForExistence(timeout: 10))
        save(app, as: "1-today")
    }

    func test2Capture() {
        // Without the sample library, which already has "cookies".
        let app = launch(tab: "capture", seedsLibrary: false)
        let input = app.textViews["capture-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("This website uses cookies for tracking.")
        app.buttons["capture-done-editing"].tap()
        let cookies = app.descendants(matching: .any)["token-3"]
        XCTAssertTrue(cookies.waitForExistence(timeout: 5))
        cookies.tap()
        app.buttons["capture-explain"].tap()
        XCTAssertTrue(app.staticTexts["insight-translation"].waitForExistence(timeout: 10))
        save(app, as: "2-capture")
    }

    func test3Word() {
        let app = launch(tab: "library")
        let phrase = app.descendants(matching: .any)["library-row-raining cats and dogs"].firstMatch
        XCTAssertTrue(phrase.waitForExistence(timeout: 10))
        phrase.tap()
        XCTAssertTrue(app.staticTexts["insight-translation"].waitForExistence(timeout: 5))
        save(app, as: "3-word")
    }

    func test4Quiz() {
        let app = launch(tab: "practice")
        let start = app.buttons["quiz-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        // A written question shows more than a listening one, whose word is only heard.
        for _ in 0..<3 {
            XCTAssertTrue(app.buttons["quiz-option-0"].waitForExistence(timeout: 10))
            if app.staticTexts["quiz-prompt"].exists { break }
            app.buttons["quiz-option-0"].tap()
            app.buttons["quiz-next"].tap()
        }
        XCTAssertTrue(app.staticTexts["quiz-prompt"].waitForExistence(timeout: 10))
        save(app, as: "4-quiz")
    }

    func test5Podcast() {
        let app = launch(tab: "practice", ["-vos-podcast", "newest"])
        XCTAssertTrue(app.staticTexts["podcast-title"].waitForExistence(timeout: 10))
        save(app, as: "5-podcast")
    }

    private func launch(tab: String, _ arguments: [String] = [], seedsLibrary: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-seed-library", seedsLibrary ? "YES" : "NO",
            "-vos-ai-stub", "YES", "-vos-store-screenshots", "YES",
            "-vos-tab", tab, "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + arguments
        app.launch()
        return app
    }

    private func save(_ app: XCUIApplication, as name: String) {
        // Let animations and the keyboard settle.
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
