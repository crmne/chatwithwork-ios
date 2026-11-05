import XCTest

/// The places the sidebar opens, against a Chat with Work server of your own:
/// Decisions keeps the sidebar button after a decision is made, rather than
/// stacking the next one with back to the one just decided; a bot the
/// sidebar opens is a place too; a bot opened from its decision's chip in
/// Decisions is a drill-down, with back to Decisions; and Decisions opened
/// again from the sidebar is the root once more.
///
/// Needs a development server reachable from the simulator, with a login
/// that has a change waiting for approval and a question from a bot named
/// "Front desk" (or CWW_UI_TEST_BOT): CWW_UI_TEST_BASE_URL,
/// CWW_UI_TEST_EMAIL and CWW_UI_TEST_PASSWORD (TEST_RUNNER_ prefixed
/// through xcodebuild). Skipped without them. It approves the change in
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
        if approve.exists {
            approve.tap()
            // The board moves on at once; a screen stacked over it may come
            // a few seconds later, when the decided chat broadcasts.
            settle(4)
            keep("decisions-moved-on")
            _ = backButton(app).waitForExistence(timeout: 10)
            settle(2)
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
        }

        // A bot from the sidebar's Bots: a place too.
        let name = environment["CWW_UI_TEST_BOT"] ?? "Front desk"
        openSidebar(app)
        let botsHalf = app.buttons["sidebar.switch.bots"]
        XCTAssertTrue(botsHalf.waitForExistence(timeout: 10))
        botsHalf.tap()
        settle(1.5)
        keep("sidebar-bots")
        let row = sidebarBot(app, named: name)
        if !row.waitForExistence(timeout: 10) { print("PLACES sidebar tree:\n\(app.debugDescription)") }
        XCTAssertTrue(row.exists, "The sidebar should list bots")
        if row.exists {
            print("PLACES sidebar bot row: \(row.label)")
            row.tap()
            settle(4)
            report("bot-from-sidebar", app)
            XCTAssertTrue(app.buttons["shell.sidebar"].exists, "A bot the sidebar opens should be a place, with the sidebar button")
            keep("bot-from-sidebar")
        }

        // A drill-down from a place: the bot's chip on its decision in
        // Decisions, pushed with back, which returns to Decisions.
        openSidebar(app)
        XCTAssertTrue(decisions.waitForExistence(timeout: 10))
        decisions.tap()
        settle(4)
        let links = app.webViews.links.matching(NSPredicate(format: "label BEGINSWITH %@", name))
        if links.count == 1 {
            // Only the bot's filter: narrow the board to it, so its decision is in focus.
            links.firstMatch.tap()
            settle(4)
        }
        let botChip = chip(in: links)
        XCTAssertTrue(botChip.exists, "\(name)'s decision should show its chip")
        report("decisions-for-bot", app)
        keep("decisions-for-bot")
        if botChip.exists {
            botChip.tap()
            settle(4)
            report("bot-from-decisions", app)
            keep("bot-from-decisions")
            let back = backButton(app)
            XCTAssertTrue(back.exists, "A bot opened from Decisions should have back")
            if back.exists {
                back.tap()
                settle(3)
                report("bot-back", app)
                XCTAssertTrue(app.buttons["shell.sidebar"].exists, "Back should return to Decisions, a place")
                keep("bot-back")
            }
        }

        // Decisions again, from the sidebar.
        openSidebar(app)
        XCTAssertTrue(decisions.waitForExistence(timeout: 10))
        decisions.tap()
        settle(5)
        report("decisions-again", app)
        XCTAssertTrue(app.buttons["shell.sidebar"].exists, "Decisions should be a place, with the sidebar button")
        XCTAssertFalse(backButton(app).exists, "Decisions should have no back")
        keep("decisions-again")
    }

    /// A bot in the sidebar's Bots: the one named, else the first.
    @MainActor
    private func sidebarBot(_ app: XCUIApplication, named name: String) -> XCUIElement {
        let rows = app.descendants(matching: .any).matching(identifier: "sidebar.bot")
        let named = rows.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        if named.exists { return named }
        if rows.firstMatch.exists { return rows.firstMatch }
        let digest = environment["CWW_UI_TEST_SIDEBAR_BOT"] ?? "Weekly digest"
        return app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", name, digest)).firstMatch
    }

    /// The lowest of the bot's links on the board, under its filter pill:
    /// its chip on the decision in focus.
    @MainActor
    private func chip(in links: XCUIElementQuery) -> XCUIElement {
        let all = links.allElementsBoundByIndex
        guard all.count > 1, let lowest = all.max(by: { $0.frame.minY < $1.frame.minY }) else { return links.element(boundBy: 99) }
        return lowest
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
