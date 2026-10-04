import XCTest

/// Word lists: making them, sharing them as files, and importing a shared file (task T30).
@MainActor
final class SharingUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-seed-library", "YES",
            "-vos-tab", "library", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + arguments
        app.launch()
        return app
    }

    /// The sample file is a German list "Reisen": Bahnhof and Fahrkarte are new, and Schlüssel is
    /// already in the sample library.
    func testImportingAWordList() {
        let app = launch(["-vos-import-sample", "YES"])
        let confirm = app.buttons["import-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Opening the file asks to import it")
        XCTAssertTrue(app.descendants(matching: .any)["import-new"].label.hasSuffix("2"))
        XCTAssertTrue(app.descendants(matching: .any)["import-existing"].label.hasSuffix("1"))
        attachScreenshot(of: app, named: "01-import")
        confirm.tap()
        let result = app.staticTexts["import-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "2 words added.")
        app.buttons["import-done"].tap()

        app.buttons["German"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["library-row-Bahnhof"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["library-row-Fahrkarte"].exists)
        app.buttons["library-lists"].tap()
        let list = app.buttons["list-row-Reisen"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(list.label.hasSuffix("3"), "The list has the existing word too: \(list.label)")
    }

    func testMakingAndSharingAList() {
        let app = launch()
        // A new list from a word's page.
        let cookies = app.descendants(matching: .any)["library-row-cookies"].firstMatch
        XCTAssertTrue(cookies.waitForExistence(timeout: 5))
        cookies.tap()
        app.buttons["detail-more"].tap()
        app.buttons["Lists…"].tap()
        app.buttons["word-lists-new"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Tech")
        app.alerts.buttons["Create"].firstMatch.tap()
        let tech = app.buttons["word-list-Tech"]
        XCTAssertTrue(tech.waitForExistence(timeout: 5))
        XCTAssertTrue(tech.isSelected, "The word joins the list it was made from")
        app.buttons["word-lists-done"].tap()

        // The list, from the Library.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["library-lists"].tap()
        let row = app.buttons["list-row-Tech"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.hasSuffix("1"), row.label)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["library-row-cookies"].waitForExistence(timeout: 5))

        // Sharing offers the file.
        app.buttons["list-more"].tap()
        app.buttons["Share List"].tap()
        let fileName = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Tech")).firstMatch
        XCTAssertTrue(fileName.waitForExistence(timeout: 10), "The share sheet names the file")
        attachScreenshot(of: app, named: "02-share")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
