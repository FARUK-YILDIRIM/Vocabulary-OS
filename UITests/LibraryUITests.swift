import XCTest

/// Library filters, search, language switch and the word detail actions (task T12).
@MainActor
final class LibraryUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testBrowsingFilteringEditingAndDeleting() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-seed-library", "YES",
            "-vos-tab", "library", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTAssertTrue(row("cookies", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(row("pitch", in: app).exists)
        XCTAssertFalse(row("Bank", in: app).exists, "German words belong to the German tab")
        attachScreenshot(of: app, named: "01-library-english")

        filter("due", in: app)
        XCTAssertTrue(row("pitch", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(row("cookies", in: app).exists)
        filter("mastered", in: app)
        XCTAssertTrue(row("ran", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(row("pitch", in: app).exists)
        filter("new", in: app)
        XCTAssertTrue(row("cookies", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(row("ran", in: app).exists)
        filter("all", in: app)

        app.buttons["German"].tap()
        let key = row("Schlüssel", in: app)
        XCTAssertTrue(key.waitForExistence(timeout: 3))
        XCTAssertFalse(row("cookies", in: app).exists)
        key.tap()

        let translation = app.staticTexts["insight-translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: 3))
        XCTAssertEqual(translation.label, "anahtar")
        app.buttons["insight-listen"].tap()
        attachScreenshot(of: app, named: "02-detail")

        app.buttons["detail-more"].tap()
        app.buttons["Edit"].tap()
        let field = app.textFields["edit-translation"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "kapı anahtarı")
        app.buttons["edit-save"].tap()
        XCTAssertTrue(app.staticTexts["kapı anahtarı"].waitForExistence(timeout: 3))
        attachScreenshot(of: app, named: "03-edited")

        app.buttons["detail-more"].tap()
        app.buttons["Delete"].tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(row("Bank", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(row("Schlüssel", in: app).exists)
        attachScreenshot(of: app, named: "04-after-delete")
    }

    func testACapturedWordAppearsInTheLibrary() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-ai-stub", "YES",
            "-vos-tab", "capture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        let input = app.textViews["capture-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("This website uses cookies for tracking.")
        app.buttons["capture-done-editing"].tap()
        app.descendants(matching: .any)["token-3"].tap()
        app.buttons["capture-explain"].tap()
        XCTAssertTrue(app.buttons["capture-save"].waitForExistence(timeout: 10))
        app.buttons["capture-save"].tap()

        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(row("cookies", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["çerez"].exists)
    }

    private func row(_ term: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["library-row-\(term)"].firstMatch
    }

    private func filter(_ name: String, in app: XCUIApplication) {
        app.buttons["library-filter-\(name)"].tap()
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
