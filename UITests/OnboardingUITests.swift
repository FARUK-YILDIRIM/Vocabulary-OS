import XCTest

/// Walks through first-launch onboarding and checks the saved languages in Settings (task T04).
@MainActor
final class OnboardingUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testOnboardingSavesNativeAndLearningLanguages() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        attachScreenshot(of: app, named: "01-welcome")
        app.buttons["Get Started"].tap()

        let turkish = app.buttons["language-tr"]
        reveal(turkish, in: app)
        turkish.tap()
        attachScreenshot(of: app, named: "02-native-language")
        app.buttons["Continue"].tap()

        let english = app.buttons["language-en"]
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["language-tr"].exists, "The native language must not be offered for learning")
        XCTAssertFalse(app.buttons["Start Learning"].isEnabled, "At least one learning language is required")
        english.tap()
        app.buttons["language-de"].tap()
        attachScreenshot(of: app, named: "03-learning-languages")
        app.buttons["Start Learning"].tap()

        XCTAssertTrue(app.staticTexts["Nothing to review yet"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "04-today")

        // iPhone shows a tab bar, iPad a floating tab bar or sidebar; the button label is the same.
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Languages"].tap()
        XCTAssertTrue(app.staticTexts["Türkçe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Deutsch"].exists)
        attachScreenshot(of: app, named: "05-language-settings")
    }

    /// SwiftUI lists create rows lazily, so off-screen rows don't exist until scrolled into view.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 10) {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        var swipes = 0
        while !element.isHittable, swipes < maxSwipes {
            list.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) is not on screen")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
