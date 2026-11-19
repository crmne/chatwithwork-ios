import XCTest

/// The signed-in shell against staging's synthetic data, as Maya in
/// Northwind Studio: sign in to her home, the drawer's sidebar page, a chat,
/// its Bots half and Settings from her menu. Screenshots are kept as
/// attachments.
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
        XCTAssertTrue(sidebar.waitForExistence(timeout: 40), "Signing in should land on the organization's home with the sidebar button")
        XCTAssertFalse(app.navigationBars.buttons["BackButton"].exists, "The home is a place, without back")
        // The home lands on Decisions, or on New chat when nothing shows there.
        let landed = app.navigationBars["Decisions"].waitForExistence(timeout: 40) || app.navigationBars["New chat"].exists
        XCTAssertTrue(landed, "Starting should land on the organization's home: Decisions or New chat")
        settle(4)
        keep("home")

        // Staging names the sidebar page, so the drawer shows the server's
        // sidebar rather than the native one (docs/server-contract.md, "The sidebar page").
        sidebar.tap()
        let page = app.webViews["sidebar.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 20), "The drawer should show staging's sidebar page")
        XCTAssertTrue(page.links["New chat"].waitForExistence(timeout: 15), "The page should be the web sidebar, with its New chat")
        XCTAssertFalse(app.buttons["sidebar.newChat"].exists, "The native sidebar should stay hidden under the page")
        settle(1.5)
        keep("sidebar")

        // Searching brings the keyboard up; after it, a row opening a chat
        // and the drawer opening again once left every element of the page
        // reported where the closed drawer had it, for VoiceOver and hit tests (#55).
        let search = page.descendants(matching: .any).matching(NSPredicate(format: "placeholderValue CONTAINS %@ OR label CONTAINS %@", "Search", "Search")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "The sidebar page should offer its search")
        search.tap()
        search.typeText("Li")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        settle(1)
        // A row's menu takes the focus, and the keyboard with it; a tap on the
        // drawer's header, beside the logo, closes the menu.
        tap(page.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Chat options")))
        settle(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.08)).tap()
        settle(1)

        let title = environment["CWW_UI_TEST_STAGING_CHAT"] ?? "Lisbon"
        let rows = page.links.matching(NSPredicate(format: "label CONTAINS %@", title))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "The sidebar should list a chat named like \(title) (CWW_UI_TEST_STAGING_CHAT)")
        tap(rows)
        settle(4)
        XCTAssertTrue(sidebar.exists, "A chat the sidebar opens is a place, with the sidebar button")
        keep("chat")
        sidebar.tap()
        settle(1.5)
        // A row and Recent's filter must be where they're drawn, for VoiceOver and hit tests.
        let row = rows.firstMatch
        XCTAssertTrue(waitUntil(5) { row.isHittable }, "The chat's row should be where it's drawn, not at \(row.frame)")
        let filters = page.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Bots"))
        XCTAssertTrue(waitUntil(5) { filters.allElementsBoundByIndex.contains { $0.isHittable } }, "Recent's Bots filter should be where it's drawn, not at \(filters.firstMatch.frame)")

        // Recent's filter: All, Chats, Bots. The page also holds a "Bots" off screen.
        let named = page.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Bots"))
        XCTAssertTrue(named.firstMatch.waitForExistence(timeout: 10), "The open drawer should offer Recent's Bots filter")
        tap(named)
        settle(2)
        keep("bots")

        let menu = page.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "open your menu")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "The page should offer the person's menu")
        tap(page.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "open your menu")))
        settle(1)
        let settings = page.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        tap(page.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Settings")))
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15), "Settings should open as a place")
        settle(3)
        keep("settings")
    }

    /// Taps the first of `query`'s elements that can be hit. After the drawer
    /// moves, WebKit can report the page's elements where they were rather than
    /// where they're drawn for a while, so a tap falls back to the first one's
    /// place.
    @MainActor
    private func tap(_ query: XCUIElementQuery) {
        var hit: XCUIElement?
        _ = waitUntil(5) {
            hit = query.allElementsBoundByIndex.first { $0.isHittable }
            return hit != nil
        }
        if let hit { hit.tap() } else { query.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { settle(0.25) }
        return condition()
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
