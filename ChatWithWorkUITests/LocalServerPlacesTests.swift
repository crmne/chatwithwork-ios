import XCTest

/// The places the sidebar opens, against a Chat with Work server of your own:
/// Decisions keeps the sidebar button after a decision is made, rather than
/// stacking the next one with back to the one just decided; a bot opened from
/// Bots has back, which returns to Bots; and Decisions opened again from
/// there is the root once more.
///
/// Needs a development server reachable from the simulator, with a login
/// that has at least one decision waiting (a change to approve) and a bot
/// named "Front desk" (or CWW_UI_TEST_BOT): CWW_UI_TEST_BASE_URL,
/// CWW_UI_TEST_EMAIL and CWW_UI_TEST_PASSWORD (TEST_RUNNER_ prefixed
/// through xcodebuild). Skipped without them. It approves the decision in
/// focus. Screenshots go to CWW_UI_TEST_SHOTS as well as the result bundle,
/// numbered in walk order.
final class LocalServerPlacesTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(environment["CWW_UI_TEST_PASSWORD"]?.isEmpty != false, "No local server login given")
    }

    @MainActor
    func testSidebarOpensPlaces() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", environment["CWW_UI_TEST_BASE_URL"] ?? "http://localhost:3000",
                               "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"]
        app.launch()
        signIn(app)
        keep("signed-in")

        // Decisions, from the sidebar.
        openSidebar(app)
        keep("sidebar")
        let decisions = app.buttons["sidebar.decisions"]
        XCTAssertTrue(decisions.waitForExistence(timeout: 20), "The sidebar should offer Decisions")
        decisions.tap()
        let approve = app.webViews.buttons["Approve"].firstMatch
        // A question in focus has no Approve: skip on to a change.
        let skip = app.webViews.links.matching(NSPredicate(format: "label BEGINSWITH 'Skip'")).firstMatch
        for _ in 0..<3 where !approve.waitForExistence(timeout: 15) && skip.exists {
            skip.tap()
        }
        XCTAssertTrue(approve.waitForExistence(timeout: 20), "Decisions should show a change to approve")
        settle(2)
        report("decisions", app)
        keep("decisions")

        // Approve the decision in focus; the board moves on to the next.
        approve.tap()
        settle(5)
        report("decisions-after-approve", app)
        keep("decisions-after-approve")
        let leftBehind = backButton(app)
        XCTAssertFalse(leftBehind.exists, "Decisions should have no back after a decision is made")
        if leftBehind.exists {
            leftBehind.tap()
            settle(3)
            report("decisions-back", app)
            keep("decisions-back")
        }

        // Bots, from the sidebar, and a bot from Bots, with back.
        openSidebar(app)
        let botsHalf = app.buttons["sidebar.switch.bots"]
        XCTAssertTrue(botsHalf.waitForExistence(timeout: 10))
        botsHalf.tap()
        let botsCard = app.buttons["sidebar.botsCard"]
        XCTAssertTrue(botsCard.waitForExistence(timeout: 10))
        settle(1)
        keep("sidebar-bots")
        botsCard.tap()
        let name = environment["CWW_UI_TEST_BOT"] ?? "Front desk"
        let bot = app.webViews.links.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(bot.waitForExistence(timeout: 20), "Bots should list \(name)")
        settle(2)
        report("bots", app)
        XCTAssertTrue(app.buttons["shell.sidebar"].exists, "Bots should be a place, with the sidebar button")
        keep("bots")
        bot.tap()
        settle(4)
        report("bot", app)
        keep("bot")
        let back = backButton(app)
        XCTAssertTrue(back.exists, "A bot opened from Bots should have back")
        if back.exists {
            back.tap()
            XCTAssertTrue(bot.waitForExistence(timeout: 10), "Back should return to Bots")
            settle(2)
            report("bot-back", app)
            keep("bot-back")
        }

        // Decisions again.
        openSidebar(app)
        XCTAssertTrue(decisions.waitForExistence(timeout: 10))
        decisions.tap()
        settle(5)
        report("decisions-again", app)
        XCTAssertTrue(app.buttons["shell.sidebar"].exists, "Decisions should be a place, with the sidebar button")
        XCTAssertFalse(backButton(app).exists, "Decisions should have no back")
        keep("decisions-again")
    }

    // MARK: Steps

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
        XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 40), "Signing in should land on a new chat")
        settle(3)
    }

    /// The sidebar button, walking back to a screen that has it if need be.
    @MainActor
    private func openSidebar(_ app: XCUIApplication) {
        let sidebar = app.buttons["shell.sidebar"]
        for _ in 0..<5 where !sidebar.exists && backButton(app).exists {
            backButton(app).tap()
            settle(2)
        }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "A screen with the sidebar button should be reachable")
        sidebar.tap()
        settle(1.5)
    }

    /// The navigation bar's back button, on whichever screen is on top.
    @MainActor
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")).firstMatch
    }

    /// What's at the leading end of the bar, in the test's log.
    @MainActor
    private func report(_ name: String, _ app: XCUIApplication) {
        let leading = app.buttons["shell.sidebar"].exists ? "sidebar button" : backButton(app).exists ? "back (\(backButton(app).label))" : "nothing"
        let title = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.identifier : ""
        print("PLACES \(name): leading=\(leading) title=\(title)")
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
