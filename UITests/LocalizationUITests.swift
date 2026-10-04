import XCTest

/// The app in Turkish (task T31): the app's, the packages' and the extension's strings come from
/// their String Catalogs.
@MainActor
final class LocalizationUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "YES", "-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"] + arguments
        app.launch()
        return app
    }

    func testOnboardingInTurkish() {
        let app = launch([])
        XCTAssertTrue(app.staticTexts["Kelimeleri karşılaştığın yerde öğren"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "01-onboarding")
    }

    func testScreensInTurkish() {
        let app = launch(["-vos-preset-profile", "tr:en,de", "-vos-seed-library", "YES", "-vos-ai-stub", "YES"])
        // A tab bar on iPhone, buttons along the top on iPad.
        func tab(_ name: String) -> XCUIElement { app.buttons[name].firstMatch }
        XCTAssertTrue(tab("Bugün").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tekrarlar"].exists)
        attachScreenshot(of: app, named: "02-today")

        tab("Yakala").tap()
        // From the VocabularyUI package's catalog.
        XCTAssertTrue(app.staticTexts["Kelimeyi bulduğun cümleyi yapıştır ya da yaz."].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "03-capture")

        tab("Alıştırma").tap()
        XCTAssertTrue(app.buttons["Testi Başlat"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "04-practice")

        tab("Kitaplık").tap()
        let cookies = app.descendants(matching: .any)["library-row-cookies"].firstMatch
        XCTAssertTrue(cookies.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "05-library")
        cookies.tap()
        XCTAssertTrue(app.buttons["Dinle"].waitForExistence(timeout: 5), "The insight card's strings come from VocabularyUI")
        attachScreenshot(of: app, named: "06-word")

        tab("Ayarlar").tap()
        XCTAssertTrue(app.buttons["settings-ai"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "07-settings")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
