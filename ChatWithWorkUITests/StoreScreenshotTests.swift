import XCTest

/// The App Store screenshots, taken from the app against a real server with
/// the synthetic demo account (`script/store/seed` in the Rails app makes
/// it: Northwind Studio, Acme, and every message are made up). Each screen
/// is kept as an attachment named `store-<n>-<screen>`, which
/// `script/screenshots` exports from the result bundle.
///
/// Needs the demo login, passed through xcodebuild as
/// TEST_RUNNER_CWW_SCREENSHOT_EMAIL and TEST_RUNNER_CWW_SCREENSHOT_PASSWORD,
/// and skips itself without them. The server defaults to staging
/// (CWW_SCREENSHOT_BASE_URL to change it).
final class StoreScreenshotTests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment

    private var baseURL: String {
        environment["CWW_SCREENSHOT_BASE_URL"] ?? "https://staging.chatwithwork.com"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(environment["CWW_SCREENSHOT_EMAIL"] == nil, "No demo login for the store screenshots")
    }

    @MainActor
    func testStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", baseURL]
        app.launch()

        signIn(app)

        // 1. A scheduled brief, answered from Slack and Drive.
        open(app, chat: "Morning Acme brief", showing: "Who owes what this week")
        keep("1-brief")

        // 2. A change waiting for approval. Tapping the open tab goes back to its list.
        tab(app, "Chats")
        open(app, chat: "Acme launch update", showing: "Approve")
        keep("2-approval")

        // 3. Every tool, one agent: the new chat page fanned out to the connected services.
        tab(app, "New chat")
        XCTAssertTrue(app.webViews.buttons["Ask me how you can help"].waitForExistence(timeout: 30))
        // The web search note shows once; the screenshot doesn't need it.
        let dismiss = app.webViews.buttons["Dismiss"].firstMatch
        if dismiss.exists { dismiss.tap() }
        settle(3)
        keep("3-new-chat")
        if app.buttons["sheet.close"].exists { app.buttons["sheet.close"].tap() }

        // 4. Schedules.
        tab(app, "Settings")
        let schedules = app.webViews.links["Schedules"].firstMatch
        XCTAssertTrue(schedules.waitForExistence(timeout: 30))
        schedules.tap()
        XCTAssertTrue(app.webViews.staticTexts["Add schedule"].waitForExistence(timeout: 30))
        settle()
        keep("4-schedules")

        // 5. Projects shared with the team.
        tab(app, "Projects")
        XCTAssertTrue(app.webViews.staticTexts["Acme launch"].waitForExistence(timeout: 30))
        settle()
        keep("5-projects")

        // 6. The chat list: the tab still shows the last chat, and a second tap goes back to the list.
        tab(app, "Chats")
        settle(1)
        tab(app, "Chats")
        XCTAssertTrue(app.webViews.staticTexts["Morning Acme brief"].waitForExistence(timeout: 30))
        settle()
        keep("6-chats")
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let signIn = app.buttons["welcome.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()

        let email = app.webViews.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 30), "The sign-in page should load in a sheet")
        email.tap()
        email.typeText(environment["CWW_SCREENSHOT_EMAIL"] ?? "")
        let password = app.webViews.secureTextFields.firstMatch
        password.tap()
        password.typeText(environment["CWW_SCREENSHOT_PASSWORD"] ?? "")
        app.webViews.buttons["Sign in"].tap()

        // Signing in lands on Chats; tap it anyway, in case the shell restored another tab.
        XCTAssertTrue(app.buttons["Chats"].firstMatch.waitForExistence(timeout: 40), "Signing in should show the tabs")
        settle(3)
        tab(app, "Chats")
        XCTAssertTrue(app.webViews.staticTexts["Morning Acme brief"].waitForExistence(timeout: 40), "Signing in should land on the chat list")
        // The sign-in notice goes away by itself.
        let toast = app.descendants(matching: .any)["toast"]
        if toast.waitForExistence(timeout: 5) { toast.tap() }
        settle()
    }

    @MainActor
    private func open(_ app: XCUIApplication, chat title: String, showing text: String) {
        let row = app.webViews.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        let shown = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        let button = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 30) || button.waitForExistence(timeout: 10), "\(title) should show \(text)")
        settle(3)
        let latest = app.webViews.buttons["Scroll to the latest message"].firstMatch
        if latest.exists && latest.isHittable {
            latest.tap()
            settle(2)
        }
    }

    /// A tab: in the tab bar on iPhone, at the top on iPad.
    @MainActor
    private func tab(_ app: XCUIApplication, _ name: String) {
        let inTabBar = app.tabBars.buttons[name]
        // A pushed page can hide the tab bar: go back to the tab's list first.
        if !inTabBar.exists && !app.buttons[name].firstMatch.exists { back(app) }
        (inTabBar.exists ? inTabBar : app.buttons[name].firstMatch).tap()
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        (back.exists ? back : app.navigationBars.buttons.element(boundBy: 0)).tap()
        settle(2)
    }

    private func settle(_ seconds: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func keep(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "store-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
