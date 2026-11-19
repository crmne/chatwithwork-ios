import XCTest

/// The sidebar page in the drawer (docs/server-contract.md, "The sidebar
/// page"), against a Chat with Work server of your own: the app starts on the
/// organization's home, the drawer shows the server's sidebar page rather
/// than the native sidebar, and a chat's row opens the chat as a place and
/// closes the drawer.
///
/// Needs a development server reachable from the simulator with a login
/// whose sidebar holds a chat named CWW_UI_TEST_CHAT: CWW_UI_TEST_BASE_URL,
/// CWW_UI_TEST_EMAIL, CWW_UI_TEST_PASSWORD (TEST_RUNNER_ prefixed through
/// xcodebuild). Skipped without them. Screenshots go to CWW_UI_TEST_SHOTS as
/// well as the result bundle.
final class LocalServerSidebarPageTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(environment["CWW_UI_TEST_PASSWORD"]?.isEmpty != false, "No local server login given")
    }

    @MainActor
    func testDrawerShowsTheSidebarPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", environment["CWW_UI_TEST_BASE_URL"] ?? "http://localhost:3000",
                               "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"]
        app.launch()
        signIn(app)
        keep("home")

        app.buttons["shell.sidebar"].tap()
        let page = app.webViews["sidebar.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 20), "The drawer should show the server's sidebar page")
        XCTAssertTrue(page.links["New chat"].waitForExistence(timeout: 10), "The page should be the web sidebar, with its New chat")
        XCTAssertFalse(app.buttons["sidebar.decisions"].exists, "The native sidebar should be hidden under the page")
        settle(1.5)
        keep("drawer")

        let title = environment["CWW_UI_TEST_CHAT"] ?? "Q4 launch plan"
        let row = page.links.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The sidebar page should list \(title)")
        row.tap()
        settle(3)
        XCTAssertFalse(page.isHittable, "Opening a row should close the drawer")
        XCTAssertTrue(app.buttons["shell.sidebar"].exists, "A chat the sidebar opens is a place, with the sidebar button")
        keep("chat")

        app.buttons["shell.sidebar"].tap()
        settle(1.5)
        keep("drawer-on-chat")
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let welcome = app.buttons["welcome.signIn"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 30))
        welcome.tap()
        let email = app.webViews.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 30))
        email.tap()
        email.typeText(environment["CWW_UI_TEST_EMAIL"] ?? "")
        let password = app.webViews.secureTextFields.firstMatch
        password.tap()
        password.typeText(environment["CWW_UI_TEST_PASSWORD"] ?? "")
        app.webViews.buttons["Sign in"].firstMatch.tap()
        XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 40), "Signing in should land on the organization's home")
        settle(3)
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func keep(_ name: String) {
        step += 1
        let file = String(format: "%02d-%@", step, name)
        let screenshot = XCUIScreen.main.screenshot()
        if let folder = environment["CWW_UI_TEST_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(file).png"))
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
