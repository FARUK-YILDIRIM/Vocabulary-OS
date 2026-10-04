import XCTest

/// A word store that can't be opened stops the app, instead of letting the learner capture into a
/// stand-in that disappears at the next launch (code review).
@MainActor
final class StoreErrorUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testALibraryThatCantBeOpenedIsAllTheAppShows() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-store-fails", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Your Library Couldn't Be Opened"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Capture"].exists, "nothing can be captured")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "01-store-error"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
