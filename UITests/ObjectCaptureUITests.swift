import XCTest

/// Capture → Object: name a photographed object and save it with the photo (task T21).
@MainActor
final class ObjectCaptureUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Uses a stand-in cup photo and canned AI answers: the Simulator has no photos, no on-device
    /// model and no image classifier.
    func testNamingAPhotographedCupSavesItWithThePhoto() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-tab", "capture",
            "-vos-capture-mode", "object", "-vos-sample-object", "YES", "-vos-ai-stub", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        let field = app.textFields["object-label-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "The photo should be shown with a label to confirm")
        let cup = app.buttons["object-label-cup"]
        if cup.exists {
            XCTAssertTrue(cup.isSelected)
        } else {
            // The iOS Simulator can't run Vision's image classifier, so the learner types the name.
            field.tap()
            field.typeText("cup\n")
        }
        attachScreenshot(of: app, named: "01-classified")

        app.buttons["language-chip-de"].tap()
        app.buttons["object-name"].tap()
        let translation = app.staticTexts["insight-translation"]
        XCTAssertTrue(translation.waitForExistence(timeout: 10))
        XCTAssertEqual(translation.label, "fincan")
        XCTAssertTrue(app.staticTexts["die Tasse"].exists)
        attachScreenshot(of: app, named: "02-named")

        reveal(app.buttons["object-save"], in: app)
        app.buttons["object-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["object-saved"].waitForExistence(timeout: 5))

        app.buttons["Library"].firstMatch.tap()
        app.buttons["German"].tap()
        let row = app.descendants(matching: .any)["library-row-die Tasse"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.images["Captured photo"].waitForExistence(timeout: 5), "The photo is saved with the word")
        attachScreenshot(of: app, named: "03-saved-with-photo")
    }

    /// With "Send object photos" on and a cloud provider in use, the model sees the photo, so the
    /// learner doesn't have to say what the object is (task T33).
    func testACloudModelThatSeesThePhotoNamesTheObjectWithoutALabel() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-tab", "settings",
            "-vos-capture-mode", "object", "-vos-sample-object", "YES", "-vos-ai-stub", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        app.buttons["settings-ai"].tap()
        app.buttons["provider-openai"].tap()
        let key = app.secureTextFields["provider-key"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.tap()
        key.typeText("sk-test-not-a-real-key")
        app.buttons["provider-save-key"].tap()
        app.buttons["provider-use"].tap()
        let notice = app.alerts.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        notice.buttons["Continue"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The setting sits below the providers, in rows the list creates only when they scroll in.
        let photos = app.switches["ai-send-photos"]
        var swipes = 0
        while !photos.exists && swipes < 10 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        reveal(photos, in: app)
        XCTAssertEqual(photos.value as? String, "0", "Photos stay on the device until the learner allows it")
        (photos.switches.firstMatch.exists ? photos.switches.firstMatch : photos).tap()
        XCTAssertEqual(photos.value as? String, "1")
        attachScreenshot(of: app, named: "04-photos-allowed")

        app.buttons["Capture"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["object-sends-photo"].waitForExistence(timeout: 20))
        let field = app.textFields["object-label-field"]
        if let label = field.value as? String, !label.isEmpty, label != field.placeholderValue {
            field.tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: label.count))
        }
        app.buttons["language-chip-de"].tap()
        XCTAssertTrue(app.buttons["object-name"].isEnabled, "With the photo, a label is optional")
        app.buttons["object-name"].tap()
        XCTAssertTrue(app.staticTexts["die Tasse"].waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "05-named-from-the-photo")
    }

    /// Scrolls until the element is on screen; the save button sits below the insight card.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
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
