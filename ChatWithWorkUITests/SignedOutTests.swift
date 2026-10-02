import XCTest

/// The signed-out flow against a real server (staging by default), which
/// needs no account: the welcome screen, then the server's sign-in page in a
/// sheet. Screenshots are kept as attachments in the result bundle.
///
/// Run with the ChatWithWorkUITests scheme. Point it elsewhere with the
/// CWW_UI_TEST_BASE_URL environment variable (TEST_RUNNER_CWW_UI_TEST_BASE_URL
/// when passed through xcodebuild).
final class SignedOutTests: XCTestCase {
    private var baseURL: String {
        ProcessInfo.processInfo.environment["CWW_UI_TEST_BASE_URL"] ?? "https://staging.chatwithwork.com"
    }

    /// Appended to screenshot names, so light and dark runs don't collide.
    private var suffix: String {
        ProcessInfo.processInfo.environment["CWW_UI_TEST_APPEARANCE"].map { "-\($0)" } ?? ""
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeThenSignInSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", baseURL]
        app.launch()

        let signIn = app.buttons["welcome.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["welcome.signUp"].exists)
        keepScreenshot(named: "welcome")

        signIn.tap()

        let email = app.webViews.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 30), "The sign-in page should load in a sheet")
        XCTAssertTrue(app.buttons["sheet.close"].waitForExistence(timeout: 5), "The sheet should have a close button")
        sleep(1)
        keepScreenshot(named: "sign-in")

        app.buttons["sheet.close"].tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSignUpSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", baseURL]
        app.launch()

        let signUp = app.buttons["welcome.signUp"]
        XCTAssertTrue(signUp.waitForExistence(timeout: 10))
        signUp.tap()

        XCTAssertTrue(app.webViews.textFields.firstMatch.waitForExistence(timeout: 30))
        sleep(1)
        keepScreenshot(named: "sign-up")
    }

    /// With no session, the tab shell sends the person to the welcome screen
    /// and opens sign-in for them.
    @MainActor
    func testExpiredSessionReturnsToSignIn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWAssumeSignedIn", "YES", "-CWWBaseURL", baseURL]
        app.launch()

        XCTAssertTrue(app.webViews.textFields.firstMatch.waitForExistence(timeout: 30), "Sign-in should open once the server says there's no session")
        XCTAssertTrue(app.buttons["welcome.signIn"].exists)
        sleep(1)
        keepScreenshot(named: "session-expired")
    }

    @MainActor
    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name + suffix
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
