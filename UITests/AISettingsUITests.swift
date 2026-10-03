import XCTest

/// Connecting a cloud provider in Settings → AI (task T16). No request leaves the Simulator:
/// UI tests keep keys in memory and never press "Test Connection".
@MainActor
final class AISettingsUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testSavingAKeyAndSwitchingToACloudProvider() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-tab", "settings",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        app.buttons["settings-ai"].tap()
        let inUse = app.staticTexts["ai-in-use"]
        XCTAssertTrue(inUse.waitForExistence(timeout: 5))
        XCTAssertTrue(inUse.label.contains("Apple Intelligence (on device)"), inUse.label)
        attachScreenshot(of: app, named: "01-ai-settings")

        app.buttons["provider-openai"].tap()
        XCTAssertFalse(app.buttons["provider-use"].isEnabled, "A key is required first")
        let key = app.secureTextFields["provider-key"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.tap()
        key.typeText("sk-test-not-a-real-key")
        app.buttons["provider-save-key"].tap()
        XCTAssertTrue(app.buttons["Remove Key"].waitForExistence(timeout: 3), "The saved key is offered for removal, never shown")
        attachScreenshot(of: app, named: "02-provider-detail")

        app.buttons["provider-use"].tap()
        let notice = app.alerts.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3), "The privacy notice comes before the first cloud use")
        attachScreenshot(of: app, named: "03-privacy-notice")
        notice.buttons["Continue"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(inUse.waitForExistence(timeout: 3))
        XCTAssertTrue(inUse.label.contains("OpenAI · gpt-6-luna"), inUse.label)
        attachScreenshot(of: app, named: "04-in-use")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
