import XCTest

/// The signed-in shell against staging's synthetic data, as Maya in
/// Northwind Studio: sign in, the new chat, the sidebar, what waits for her,
/// a chat, Bots and Settings. Screenshots are kept as attachments.
///
/// Needs the demo login's password in CWW_UI_TEST_STAGING_PASSWORD
/// (TEST_RUNNER_CWW_UI_TEST_STAGING_PASSWORD through xcodebuild); skipped
/// without it. Never put real data in front of it: staging is synthetic.
final class StagingTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var baseURL: String { environment["CWW_UI_TEST_BASE_URL"] ?? "https://staging.chatwithwork.com" }
    private var email: String { environment["CWW_UI_TEST_STAGING_EMAIL"] ?? "maya@northwind.example" }
    private var suffix: String { environment["CWW_UI_TEST_APPEARANCE"].map { "-\($0)" } ?? "" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(environment["CWW_UI_TEST_STAGING_PASSWORD"]?.isEmpty != false, "No staging password given")
    }

    @MainActor
    func testSidebarShellOnStaging() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", baseURL, "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"]
        app.launch()

        app.buttons["welcome.signIn"].tap()
        let emailField = app.webViews.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 30))
        emailField.tap()
        emailField.typeText(email)
        let password = app.webViews.secureTextFields.firstMatch
        password.tap()
        password.typeText(environment["CWW_UI_TEST_STAGING_PASSWORD"] ?? "")
        app.webViews.buttons["Sign in"].firstMatch.tap()

        let sidebar = app.buttons["shell.sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 40), "Signing in should land on a new chat with the sidebar button")
        settle(4)
        keep("new-chat")

        sidebar.tap()
        XCTAssertTrue(app.buttons["sidebar.newChat"].waitForExistence(timeout: 15), "The sidebar should load its JSON from staging")
        settle(1.5)
        keep("sidebar")

        app.buttons["sidebar.waiting"].tap()
        settle(1)
        keep("waiting")

        let chat = app.buttons.matching(identifier: "sidebar.chat").firstMatch
        if chat.waitForExistence(timeout: 5) {
            chat.tap()
            settle(4)
            keep("chat")
            sidebar.tap()
        }

        let bots = app.buttons["sidebar.bots"]
        XCTAssertTrue(bots.waitForExistence(timeout: 10))
        bots.tap()
        settle(4)
        keep("bots")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        sidebar.tap()
        app.buttons["sidebar.person"].tap()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["sheet.close"].waitForExistence(timeout: 15), "Settings should come up as a sheet")
        settle(4)
        keep("settings")
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func keep(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        // Also as files, where the result bundle drops attachments (seen on iPad simulators).
        if let folder = environment["CWW_UI_TEST_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("staging-\(name)\(suffix).png"))
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "staging-\(name)\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
