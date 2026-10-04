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

    /// A provider of the learner's own (task T34): plain http is fine on this device, refused for a
    /// server on the internet.
    func testAddingAProviderOfYourOwn() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-tab", "settings",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        app.buttons["settings-ai"].tap()
        let add = app.buttons["provider-add"]
        scroll(to: add, in: app)
        add.tap()

        let name = app.textFields["custom-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ollama")
        let address = app.textFields["custom-address"]
        address.tap()
        let publicAddress = "http://ollama.example.com/v1"
        address.typeText(publicAddress)
        app.buttons["custom-add"].tap()
        XCTAssertTrue(app.staticTexts["custom-error"].waitForExistence(timeout: 3), "Plain http to the internet is refused")
        attachScreenshot(of: app, named: "05-refused-address")

        address.tap()
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: publicAddress.count))
        address.typeText("http://localhost:11434/v1")
        app.buttons["custom-add"].tap()

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'provider-custom-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Ollama"), row.label)
        attachScreenshot(of: app, named: "06-own-provider")
        row.tap()

        let model = app.textFields["provider-other-model"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.tap()
        model.typeText("llama4")
        let use = app.buttons["provider-use"]
        scroll(to: use, in: app)
        use.tap()
        let notice = app.alerts.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3), "A provider of your own may be on the internet too")
        notice.buttons["Continue"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let inUse = app.staticTexts["ai-in-use"]
        var swipes = 0
        while !inUse.exists && swipes < 10 {
            app.swipeDown()
            swipes += 1
        }
        XCTAssertTrue(inUse.waitForExistence(timeout: 3))
        XCTAssertTrue(inUse.label.contains("Ollama · llama4"), inUse.label)
        attachScreenshot(of: app, named: "07-own-provider-in-use")
    }

    /// Scrolls until the element can be tapped; lists create rows only when they scroll in.
    private func scroll(to element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
