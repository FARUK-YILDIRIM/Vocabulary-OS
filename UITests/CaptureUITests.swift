import XCTest

/// Capture → explain → save in the Capture tab (task T11).
@MainActor
final class CaptureUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Uses canned AI answers, so it checks the UI flow on any machine.
    func testCapturingAWordFromASentence() {
        let app = launch(extraArguments: ["-vos-ai-stub", "YES"])
        enterSentenceAndSelectCookies(in: app)

        XCTAssertTrue(app.buttons["language-chip-en"].isSelected, "English should be detected")
        attachScreenshot(of: app, named: "01-selected")

        app.buttons["capture-explain"].tap()
        let translation = app.staticTexts["insight-translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: 10))
        XCTAssertEqual(translation.label, "çerez")
        attachScreenshot(of: app, named: "02-explained")

        app.buttons["Show Examples"].tap()
        XCTAssertTrue(app.staticTexts["Examples"].waitForExistence(timeout: 5))

        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-saved"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "03-saved")
    }

    /// The real on-device model; skipped where Apple Intelligence isn't available to the Simulator.
    func testCapturingWithTheOnDeviceModel() throws {
        let app = launch(extraArguments: [])
        enterSentenceAndSelectCookies(in: app)
        app.buttons["capture-explain"].tap()

        let translation = app.staticTexts["insight-translation"]
        let error = app.descendants(matching: .any)["capture-error"]
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, !translation.exists, !error.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if error.exists {
            attachScreenshot(of: app, named: "on-device-unavailable")
            throw XCTSkip("The on-device model is not available in this Simulator")
        }
        XCTAssertTrue(translation.exists)
        attachScreenshot(of: app, named: "04-on-device-explained")
        app.buttons["capture-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-saved"].waitForExistence(timeout: 5))
    }

    private func launch(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-tab", "capture",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + extraArguments
        app.launch()
        return app
    }

    private func enterSentenceAndSelectCookies(in app: XCUIApplication) {
        let input = app.textViews["capture-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("This website uses cookies for tracking.")
        app.buttons["capture-done-editing"].tap()

        let cookies = app.descendants(matching: .any)["token-3"]
        XCTAssertTrue(cookies.waitForExistence(timeout: 5))
        cookies.tap()
        XCTAssertEqual(app.staticTexts["capture-term"].label, "cookies")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
