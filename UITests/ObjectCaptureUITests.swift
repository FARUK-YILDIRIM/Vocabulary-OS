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
