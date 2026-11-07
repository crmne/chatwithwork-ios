import XCTest

/// New chat, New bot and Decisions from outside the app, against the
/// playground (Playground/server.py): the Home Screen's quick actions, the
/// Shortcuts app and Spotlight, cold and warm, signed in, signed out, with the
/// session gone, and in another organization. Screenshots are kept as attachments.
///
/// iOS launches the app itself here, so it gets no launch arguments: build
/// with `CWW_BASE_URL = http:/$()/localhost:8765` in Config/Local.xcconfig and
/// set TEST_RUNNER_CWW_UI_TEST_SHORTCUTS=1. Skipped otherwise.
final class ShortcutsTests: XCTestCase {
    private var playground: String {
        ProcessInfo.processInfo.environment["CWW_UI_TEST_PLAYGROUND"] ?? "http://localhost:8765"
    }

    /// Appended to screenshot names, so light and dark runs don't collide.
    private var suffix: String {
        ProcessInfo.processInfo.environment["CWW_UI_TEST_APPEARANCE"].map { "-\($0)" } ?? ""
    }

    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    @MainActor private lazy var app = XCUIApplication()
    private let appName = "CWW Dev"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CWW_UI_TEST_SHORTCUTS"] != nil, "Needs a build pointed at the playground")
        try XCTSkipUnless((try? Data(contentsOf: URL(string: "\(playground)/users/sign_in")!)) != nil, "The playground isn't running at \(playground)")
    }

    // MARK: Quick actions

    @MainActor
    func testQuickActionsWarm() throws {
        signIn()
        XCUIDevice.shared.press(.home)
        quickAction("Decisions")
        expectDecisions()
        keep("warm-decisions")

        XCUIDevice.shared.press(.home)
        quickAction("New bot")
        expectNewBot()
        keep("warm-new-bot")

        // Over New bot's sheet, the other two still arrive; the same one doesn't stack.
        XCUIDevice.shared.press(.home)
        quickAction("New bot")
        expectNewBot()
        XCUIDevice.shared.press(.home)
        quickAction("New chat")
        expectNewChat()
        keep("warm-new-chat")
        XCTAssertFalse(app.buttons["sheet.close"].exists, "New bot's sheet should have gone")

        // Back in the new chat already on screen, what's typed stays.
        app.textViews["composer.text"].typeText("Half a thought")
        XCUIDevice.shared.press(.home)
        quickAction("New chat")
        expectNewChat()
        XCTAssertEqual(app.textViews["composer.text"].value as? String, "Half a thought")

        // From an open sidebar too.
        app.buttons["shell.sidebar"].tap()
        XCTAssertTrue(app.buttons["sidebar.decisions"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        quickAction("Decisions")
        expectDecisions()
    }

    @MainActor
    func testQuickActionsCold() throws {
        signIn()
        for (title, expect) in [("New chat", expectNewChat), ("New bot", expectNewBot), ("Decisions", expectDecisions)] as [(String, () -> Void)] {
            app.terminate()
            quickAction(title)
            expect()
            keep("cold-\(title)")
        }
    }

    /// The icon's menu itself, for the screenshot.
    @MainActor
    func testQuickActionsMenu() throws {
        signIn()
        XCUIDevice.shared.press(.home)
        pressIcon()
        for title in ["New chat", "New bot", "Decisions"] {
            XCTAssertTrue(springboard.buttons[title].waitForExistence(timeout: 10), "\(title) should be on the icon's menu")
        }
        keep("menu")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
    }

    @MainActor
    func testSignedOut() throws {
        for (title, expect) in [("New chat", expectNewChat), ("New bot", expectNewBot), ("Decisions", expectDecisions)] as [(String, () -> Void)] {
            launchFresh()
            app.terminate()
            quickAction(title)
            finishSigningIn()
            expect()
            keep("signed-out-\(title)")
        }

        // Warm: from the welcome screen.
        launchFresh()
        XCUIDevice.shared.press(.home)
        quickAction("Decisions")
        finishSigningIn()
        expectDecisions()
    }

    @MainActor
    func testSessionGone() throws {
        signIn()
        for (title, expect) in [("New bot", expectNewBot), ("Decisions", expectDecisions), ("New chat", expectNewChat)] as [(String, () -> Void)] {
            app.terminate()
            _ = try Data(contentsOf: URL(string: "\(playground)/expire_sessions")!)
            quickAction(title)
            finishSigningIn()
            expect()
        }
    }

    @MainActor
    func testAnotherOrganization() throws {
        signIn()
        switchToInitech()
        XCUIDevice.shared.press(.home)
        quickAction("Decisions")
        expectDecisions()
        XCTAssertEqual(organizationOnScreen(), "Initech", "Decisions should open in the organization on screen")

        XCUIDevice.shared.press(.home)
        quickAction("New bot")
        expectNewBot()
        app.buttons["sheet.close"].tap()

        // Cold, in the one used last.
        app.terminate()
        quickAction("Decisions")
        expectDecisions()
        XCTAssertEqual(organizationOnScreen(), "Initech", "A cold start should stay in the organization used last")
    }

    // MARK: The Shortcuts app

    @MainActor
    func testShortcutsApp() throws {
        signIn()

        // Warm.
        for (title, expect) in [("Decisions", expectDecisions), ("New bot", expectNewBot), ("New chat", expectNewChat)] as [(String, () -> Void)] {
            runInShortcutsApp(title)
            expect()
            keep("intent-warm-\(title)")
        }
        // Cold.
        for (title, expect) in [("New chat", expectNewChat), ("New bot", expectNewBot), ("Decisions", expectDecisions)] as [(String, () -> Void)] {
            app.terminate()
            runInShortcutsApp(title)
            expect()
            keep("intent-cold-\(title)")
        }
    }

    // MARK: Spotlight

    @MainActor
    func testSpotlight() throws {
        signIn()
        XCUIDevice.shared.press(.home)
        springboard.swipeDown()
        let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
        XCTAssertTrue(spotlight.wait(for: .runningForeground, timeout: 10))
        spotlight.typeText("Decisions")
        // The Top Hit: the app's Decisions, with the app's mark on it.
        let topHit = spotlight.cells.matching(NSPredicate(format: "identifier CONTAINS %@", "AppViewResultCell")).firstMatch
        XCTAssertTrue(topHit.waitForExistence(timeout: 15), "Spotlight should offer Decisions as its Top Hit")
        XCTAssertTrue(topHit.staticTexts["Decisions"].exists)
        keep("spotlight")
        // Return opens the Top Hit, as the field's "Open" says.
        spotlight.typeText("\n")
        expectDecisions()
    }

    // MARK: What each should show

    @MainActor
    private func expectNewChat() {
        let field = app.textViews["composer.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "New chat should show its composer")
        let focused = wait(until: { self.hasFocus(field) })
        if !focused { keep("no-focus") }
        XCTAssertTrue(focused, "New chat's composer should have the keyboard")
        XCTAssertTrue(app.buttons["composer.dictate"].exists, "Dictation should be one tap away")
        XCTAssertTrue(app.buttons["composer.dictate"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["composer.dictation"].exists, "Nothing should start listening by itself")
        XCTAssertTrue(app.buttons["shell.sidebar"].exists, "New chat is a place")
    }

    @MainActor
    private func hasFocus(_ element: XCUIElement) -> Bool {
        element.exists && (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    @MainActor
    private func expectNewBot() {
        XCTAssertTrue(app.navigationBars["New bot"].waitForExistence(timeout: 30), "New bot should open")
        XCTAssertTrue(app.buttons["sheet.close"].exists, "New bot is a sheet")
    }

    @MainActor
    private func expectDecisions() {
        XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 30), "Decisions should open")
        XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 10), "Decisions is a place, with the sidebar button")
        XCTAssertFalse(app.buttons["sheet.close"].exists, "Decisions isn't a sheet")
    }

    // MARK: Getting there

    @MainActor
    private func launchFresh() {
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", playground, "-CWWAskForNotifications", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.signIn"].waitForExistence(timeout: 30))
    }

    @MainActor
    private func signIn() {
        launchFresh()
        app.buttons["welcome.signIn"].tap()
        finishSigningIn()
        XCTAssertTrue(app.textViews["composer.text"].waitForExistence(timeout: 30))
        let toast = app.descendants(matching: .any)["toast"]
        if toast.waitForExistence(timeout: 3) { toast.tap() }
    }

    @MainActor
    private func finishSigningIn() {
        let signIn = app.webViews.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 30), "The sign-in sheet should come up")
        signIn.tap()
    }

    @MainActor
    private func switchToInitech() {
        app.buttons["shell.sidebar"].tap()
        let person = app.buttons["sidebar.person"]
        XCTAssertTrue(person.waitForExistence(timeout: 10))
        person.tap()
        let initech = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Initech")).firstMatch
        XCTAssertTrue(initech.waitForExistence(timeout: 10))
        initech.tap()
        XCTAssertTrue(app.textViews["composer.text"].waitForExistence(timeout: 30))
        XCTAssertEqual(organizationOnScreen(), "Initech")
    }

    /// The organization the sidebar's person row names.
    @MainActor
    private func organizationOnScreen() -> String {
        app.buttons["shell.sidebar"].tap()
        let person = app.buttons["sidebar.person"]
        XCTAssertTrue(person.waitForExistence(timeout: 10))
        let label = person.label
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        return ["Acme", "Initech"].first { label.contains($0) } ?? label
    }

    @MainActor
    private func pressIcon() {
        let icon = springboard.icons[appName]
        XCTAssertTrue(icon.waitForExistence(timeout: 20), "\(appName) should be on the Home Screen")
        var swipes = 0
        while !icon.isHittable, swipes < 6 {
            springboard.swipeLeft()
            swipes += 1
        }
        icon.press(forDuration: 1.5)
    }

    @MainActor
    private func quickAction(_ title: String) {
        pressIcon()
        let action = springboard.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 10), "\(title) should be on the icon's menu")
        action.tap()
    }

    /// Runs one of the app's App Shortcuts from its page in the Shortcuts app.
    @MainActor
    private func runInShortcutsApp(_ title: String) {
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.activate()
        let welcome = shortcuts.buttons["Continue"]
        if welcome.waitForExistence(timeout: 3) { welcome.tap() }
        var tile = shortcuts.buttons[title].firstMatch
        if !tile.waitForExistence(timeout: 3) {
            let library = shortcuts.buttons["BackButton"]
            if library.waitForExistence(timeout: 3) { library.tap() }
            keep("library")
            let page = shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label == %@", appName)).firstMatch
            var swipes = 0
            while !page.exists, swipes < 5 {
                shortcuts.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(page.waitForExistence(timeout: 10), "The Shortcuts app should list \(appName)")
            page.tap()
            tile = shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "The Shortcuts app should offer \(title)")
        keep("shortcuts-app")
        tile.tap()
    }

    @MainActor
    private func wait(until condition: @escaping () -> Bool, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    @MainActor
    private func keep(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name + suffix
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
