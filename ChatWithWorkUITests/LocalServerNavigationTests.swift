import XCTest

/// Every kind of navigation the app makes, one at a time, for recording
/// what shows while each page loads: a place from the sidebar, a drill-down,
/// a tab, a sheet, back. Each navigation is one recording.
///
/// Needs a development server reachable from the simulator, with a login
/// whose organization has a bot named "Inbox triage", a project "Acme
/// launch" and a chat "Long launch notes" (CWW_UI_TEST_BOT,
/// CWW_UI_TEST_PROJECT and CWW_UI_TEST_CHAT name others, and
/// CWW_UI_TEST_ACCOUNT its slug):
/// CWW_UI_TEST_BASE_URL, CWW_UI_TEST_EMAIL and CWW_UI_TEST_PASSWORD
/// (TEST_RUNNER_ prefixed through xcodebuild). Skipped without them.
///
/// With CWW_UI_TEST_NAV_DIR, a recorder outside the simulator films each
/// navigation: before one, the test writes `<name>.ready` there and waits
/// for `<name>.recording`, holds the screen still for a second, navigates,
/// waits for the page, and writes `<name>.done`. CWW_UI_TEST_NAV_ONLY names
/// the navigations to record, comma separated (the rest still run, to get
/// there); all of them without it.
final class LocalServerNavigationTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(environment["CWW_UI_TEST_PASSWORD"]?.isEmpty != false, "No local server login given")
    }

    @MainActor
    func testEveryKindOfNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", environment["CWW_UI_TEST_BASE_URL"] ?? "http://localhost:3000",
                               "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"]
        app.launch()
        signIn(app)

        let bot = environment["CWW_UI_TEST_BOT"] ?? "Inbox triage"
        let project = environment["CWW_UI_TEST_PROJECT"] ?? "Acme launch"
        let chat = environment["CWW_UI_TEST_CHAT"] ?? "Long launch notes"

        // Places from the sidebar, and what they lead to.
        openSidebar(app)
        navigate("01-decisions") { tap(app.buttons["sidebar.decisions"]) }

        // Bots, as a place. The sidebar has no row for the Bots page while
        // the server offers its Bots half, so the app's own link opens it,
        // which routes it as the sidebar's places are.
        let account = environment["CWW_UI_TEST_ACCOUNT"] ?? "205896759"
        navigate("02-bots") { XCUIDevice.shared.system.open(URL(string: "chatwithwork://open?path=/\(account)/bots")!) }
        navigate("03-bot") { tap(webLink(app, bot)) }
        navigate("04-bot-tab") { tap(webLink(app, "Setup")) }
        navigate("13-back") { tap(backButton(app)) }

        openSidebar(app)
        tap(app.buttons["sidebar.list"])
        settle(1)
        navigate("05-projects") { tap(app.buttons["All projects…"].firstMatch) }
        navigate("06-project") { tap(webLink(app, project)) }

        // New bot, a sheet: the sidebar offers it beside the bots.
        openSidebar(app)
        tap(app.buttons["sidebar.switch.bots"])
        settle(1)
        navigate("12-modal") { tap(app.buttons["sidebar.newBot"]) }
        tap(app.buttons["sheet.close"].firstMatch)
        settle(2)

        openSidebar(app)
        tap(app.buttons["sidebar.person"])
        settle(1)
        navigate("07-settings") { tap(app.buttons["Settings"].firstMatch) }
        navigate("08-settings-tab") { tap(webLink(app, "Profile")) }

        openSidebar(app)
        if app.buttons["sidebar.switch.chats"].exists {
            tap(app.buttons["sidebar.switch.chats"])
            settle(1)
        }
        // The chat is in a project: show the project's chats.
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'sidebar.chat' AND label CONTAINS %@", chat)).firstMatch
        if !row.waitForExistence(timeout: 3) {
            tap(app.buttons["sidebar.list"])
            settle(1)
            tap(app.buttons[project].firstMatch)
            settle(3)
        }
        navigate("09-chat") { tap(app.buttons.matching(NSPredicate(format: "identifier == 'sidebar.chat' AND label CONTAINS %@", chat)).firstMatch) }
        navigate("11-panel") { tap(panelButton(app)) }
        // The panel is a sheet over the chat.
        if app.buttons["sheet.close"].exists { tap(app.buttons["sheet.close"].firstMatch) } else { app.swipeDown() }
        settle(2)

        openSidebar(app)
        navigate("10-new-chat") { tap(app.buttons["sidebar.newChat"].firstMatch) }

        openSidebar(app)
        tap(app.buttons["sidebar.list"])
        settle(1)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "My chats")).firstMatch)
        settle(3)
        navigate("14-chat-list") { tap(app.buttons["sidebar.seeAll"].firstMatch) }
    }

    // MARK: Recording

    private var only: Set<String>? {
        environment["CWW_UI_TEST_NAV_ONLY"].map { Set($0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }) }
    }

    /// One navigation, filmed when a recorder is listening.
    @MainActor
    private func navigate(_ name: String, _ action: () -> Void) {
        let app = XCUIApplication()
        print("NAV \(name): start, bar=\(barTitle(app))")
        guard let folder = environment["CWW_UI_TEST_NAV_DIR"], only?.contains(where: { name.hasPrefix($0) }) ?? true else {
            action()
            settle(4)
            print("NAV \(name): end, bar=\(barTitle(app))")
            return
        }
        let dir = URL(fileURLWithPath: folder)
        let manager = FileManager.default
        manager.createFile(atPath: dir.appendingPathComponent("\(name).ready").path, contents: nil)
        let recording = dir.appendingPathComponent("\(name).recording").path
        let deadline = Date().addingTimeInterval(30)
        while !manager.fileExists(atPath: recording) && Date() < deadline {
            settle(0.1)
        }
        XCTAssertTrue(manager.fileExists(atPath: recording), "The recorder should start for \(name)")
        settle(1)
        action()
        settle(4.5)
        // A slow page keeps its skeleton longer: film until it has gone.
        let skeleton = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["page.skeleton", "chat.skeleton"])).firstMatch
        let loaded = Date().addingTimeInterval(8)
        while skeleton.exists && Date() < loaded {
            settle(0.25)
        }
        settle(1)
        manager.createFile(atPath: dir.appendingPathComponent("\(name).done").path, contents: nil)
        // The recorder stops and writes its file before the next navigation's preparation.
        settle(1.5)
        print("NAV \(name): end, bar=\(barTitle(app))")
    }

    // MARK: Steps

    @MainActor
    private func barTitle(_ app: XCUIApplication) -> String {
        let bar = app.navigationBars.firstMatch
        return bar.exists ? bar.identifier : "-"
    }

    @MainActor
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForExistence(timeout: 20) {
            print("NAV missing \(element) in:\n\(XCUIApplication().debugDescription)")
            XCTFail("Missing \(element)", file: file, line: line)
            return
        }
        element.tap()
    }

    @MainActor
    private func webLink(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.webViews.links.matching(NSPredicate(format: "label BEGINSWITH[c] %@ OR label CONTAINS[c] %@", label, " " + label)).firstMatch
    }

    /// The bar button that opens the panel beside a chat.
    @MainActor
    private func panelButton(_ app: XCUIApplication) -> XCUIElement {
        let named = environment["CWW_UI_TEST_PANEL_BUTTON"] ?? "Side chats and more"
        return app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", named)).firstMatch
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
        XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 40), "Signing in should land on a new chat")
        settle(4)
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

    @MainActor
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")).firstMatch
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
