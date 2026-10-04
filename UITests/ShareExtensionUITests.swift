import XCTest

/// Sharing text from another app saves a word through the Share extension, and the app imports it
/// when it becomes active (task T17).
///
/// The Simulator has no Notes app, so the text is shared from Reminders.
@MainActor
final class ShareExtensionUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testSharedTextIsSavedAndImported() {
        // Launching the app hands the extension its test hooks: canned AI answers and this profile.
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-ai-stub", "YES", "-vos-shared-inbox", "YES",
            "-vos-tab", "library", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()

        let reminders = XCUIApplication(bundleIdentifier: "com.apple.reminders")
        share("This website uses cookies for tracking.", from: reminders)
        let extensionCell = reminders.cells["Vocabulary-OS"]
        XCTAssertTrue(extensionCell.waitForExistence(timeout: 5))
        extensionCell.tap()

        let cookies = reminders.descendants(matching: .any)["token-3"]
        XCTAssertTrue(cookies.waitForExistence(timeout: 10))
        attach(reminders, "01-extension-opened")
        cookies.tap()
        reminders.buttons["capture-explain"].tap()
        XCTAssertTrue(reminders.buttons["capture-save"].waitForExistence(timeout: 10))
        reminders.buttons["capture-save"].tap()
        XCTAssertTrue(reminders.descendants(matching: .any)["capture-saved"].waitForExistence(timeout: 5))
        attach(reminders, "02-extension-saved")
        reminders.buttons["share-done"].tap()
        reminders.terminate()

        app.activate()
        let row = app.descendants(matching: .any)["library-row-cookies"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["çerez"].exists)
        attach(app, "03-imported")
    }

    /// Types the text into a new reminder, selects it and opens the share sheet.
    private func share(_ text: String, from reminders: XCUIApplication) {
        reminders.launch()
        let welcome = reminders.buttons["Continue"]
        if welcome.waitForExistence(timeout: 3) {
            welcome.tap()
        }
        let newReminder = reminders.buttons["New Reminder"]
        XCTAssertTrue(newReminder.waitForExistence(timeout: 5))
        newReminder.tap()
        reminders.typeText(text)

        reminders.textFields["Title"].tap(withNumberOfTaps: 3, numberOfTouches: 1)
        let more = reminders.buttons["Forward"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        let share = reminders.buttons["Share…"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        share.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
