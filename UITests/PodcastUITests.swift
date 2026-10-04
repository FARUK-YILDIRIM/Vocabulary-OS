import XCTest

/// A podcast over the sample words, from setup to the end of the episode (task T28).
@MainActor
final class PodcastUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Canned AI answers write a twelve-line dialogue: two lines per part and one more line for each
    /// of the four English words.
    func testCreatingAndPlayingAPodcast() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "YES", "-vos-preset-profile", "tr:en,de", "-vos-seed-library", "YES", "-vos-ai-stub", "YES",
            "-vos-tab", "practice", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            // The last choices are remembered on the device; these keep the run the same everywhere.
            "-podcast.level", "a2", "-podcast.length", "short", "-podcast.style", "dialogue", "-podcast.speed", "1.2",
        ]
        app.launch()

        let newPodcast = app.buttons["practice-new-podcast"]
        XCTAssertTrue(newPodcast.waitForExistence(timeout: 5))
        newPodcast.tap()

        // Due words come first, then recent ones: all four English words.
        let count = app.staticTexts["podcast-word-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.hasSuffix("4 words"), count.label)
        attachScreenshot(of: app, named: "01-setup")
        app.buttons["podcast-create"].tap()

        let title = app.staticTexts["podcast-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 30), "The episode should open in the player")
        XCTAssertEqual(title.label, "A Day in Town")
        let position = app.staticTexts["podcast-position"]
        XCTAssertEqual(position.label, "Line 1 of 12")
        attachScreenshot(of: app, named: "02-player")

        // A saved word in the transcript opens its detail.
        let link = app.links["cookies"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "The transcript should link the saved word")
        link.tap()
        XCTAssertTrue(app.navigationBars["cookies"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "03-word")
        app.buttons["podcast-word-done"].tap()

        // Play, skip a few lines, and let the rest play to the end: the player then starts over.
        let play = app.buttons["podcast-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertEqual(play.label, "Pause")
        attachScreenshot(of: app, named: "04-playing")
        for _ in 0..<6 {
            app.buttons["podcast-next"].tap()
        }
        expectation(for: NSPredicate(format: "label == %@", "Line 12 of 12"), evaluatedWith: position)
        waitForExpectations(timeout: 60)
        expectation(for: NSPredicate(format: "label == %@", "Play"), evaluatedWith: play)
        waitForExpectations(timeout: 30)
        XCTAssertEqual(position.label, "Line 1 of 12")

        // The new episode is listed above the sample one, and can be deleted.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        let allEpisodes = app.buttons["practice-all-podcasts"]
        XCTAssertTrue(allEpisodes.waitForExistence(timeout: 10))
        allEpisodes.tap()
        let rows = app.buttons.matching(identifier: "podcast-list-episode")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.element(boundBy: 0).label.hasPrefix("A Day in Town"), rows.element(boundBy: 0).label)
        attachScreenshot(of: app, named: "05-episodes")
        rows.element(boundBy: 0).swipeLeft()
        app.buttons["Delete"].tap()
        expectation(for: NSPredicate(format: "count == 1"), evaluatedWith: rows)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(rows.element(boundBy: 0).label.hasPrefix("A Rainy Day at the Office"))
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
