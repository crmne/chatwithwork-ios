import XCTest

/// New chat as a sheet, like New bot (path configuration v3), against a Chat
/// with Work server of your own: the app starts on Decisions, the bar's New
/// chat brings its sheet up over it with Cancel and the app's composer,
/// closing it (Cancel, a swipe down) keeps what was typed for the next New
/// chat, the sidebar's New chat opens the same sheet, and sending from it
/// closes the sheet and makes the new chat the root, with the sidebar button
/// and no back.
///
/// Needs a development server reachable from the simulator and a login:
/// CWW_UI_TEST_BASE_URL, CWW_UI_TEST_EMAIL and CWW_UI_TEST_PASSWORD
/// (TEST_RUNNER_ prefixed through xcodebuild). Skipped without them. It sends
/// one question, which starts a chat. Screenshots go to CWW_UI_TEST_SHOTS as
/// well as the result bundle, numbered in walk order.
final class LocalServerNewChatTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(environment["CWW_UI_TEST_PASSWORD"]?.isEmpty != false, "No local server login given")
    }

    @MainActor
    func testNewChatIsASheetOverThePlace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", environment["CWW_UI_TEST_BASE_URL"] ?? "http://localhost:3000",
                               "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"]
        app.launch()
        signIn(app)
        keep("home")
        XCTAssertFalse(app.buttons["sheet.close"].exists, "The app should start on a place, not New chat's sheet")

        // The bar's New chat: a sheet over the place, with Cancel and the composer.
        let newChat = app.buttons["shell.newChat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 10))
        newChat.tap()
        let close = app.buttons["sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "New chat should come up as a sheet with Cancel")
        XCTAssertTrue(app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 20), "The sheet should carry the app's composer")
        keep("new-chat-opening")
        settle(3)
        keep("new-chat-sheet")
        // Decisions' All clear under the sheet has the app's composer too: the sheet's is the one that takes the keyboard.
        var field = focusSheetField(app)

        field.typeText("Draft that should stay")
        settle(1)
        keep("new-chat-typing")

        // The + sheet inside New chat's sheet.
        let plus = sheetButton(app, "composer.plus")
        if plus.exists {
            plus.tap()
            settle(1.5)
            keep("new-chat-plus")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
            settle(1.5)
        }

        // Cancel keeps the words for the next New chat.
        close.tap()
        settle(1.5)
        XCTAssertFalse(close.exists, "Cancel should close the sheet")
        keep("after-cancel")

        newChat.tap()
        XCTAssertTrue(app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 20))
        settle(2)
        field = focusSheetField(app)
        XCTAssertEqual(field.value as? String, "Draft that should stay", "New chat should open with the words left in it")
        keep("draft-back")

        // A swipe down closes it too (the first lets go of the keyboard, if it's up).
        for _ in 0..<3 where close.exists {
            // From the sheet's own bar, beside Cancel, down to the foot of the screen.
            let bar = close.coordinate(withNormalizedOffset: CGVector(dx: 4, dy: 0.5))
            bar.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            settle(1.5)
        }
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), "A swipe down should close the sheet")
        keep("after-swipe")

        // The sidebar's New chat: the same sheet.
        openSidebar(app)
        keep("sidebar")
        let sidebarNewChat = app.links.matching(NSPredicate(format: "label CONTAINS 'New chat'")).firstMatch
        if sidebarNewChat.waitForExistence(timeout: 30) {
            sidebarNewChat.tap()
        } else {
            app.buttons["sidebar.newChat"].tap()
        }
        XCTAssertTrue(close.waitForExistence(timeout: 10), "The sidebar's New chat should be the sheet too")
        XCTAssertTrue(app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 20))
        settle(2)
        keep("sidebar-new-chat")

        // Sending: the sheet closes and the chat replaces the root.
        // The words left in it go out as they are (a tap puts the caret where it lands, so nothing is added).
        field = focusSheetField(app)
        XCTAssertEqual(field.value as? String, "Draft that should stay", "The sidebar's New chat should open with the words left in it too")
        sheetButton(app, "composer.send").tap()
        let sidebar = app.buttons["shell.sidebar"]
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: close)
        waitForExpectations(timeout: 20)
        settle(3)
        keep("sent")
        XCTAssertTrue(sidebar.exists, "The new chat should be the root, with the sidebar button")
        XCTAssertFalse(backButton(app).exists, "The new chat should have no back")
        print("NEWCHAT sent: title=\(app.navigationBars.firstMatch.identifier)")

        // The sent words are gone from the next New chat.
        newChat.tap()
        XCTAssertTrue(app.textViews["composer.text"].firstMatch.waitForExistence(timeout: 20))
        settle(2)
        field = focusSheetField(app)
        XCTAssertNotEqual(field.value as? String, "Draft that should stay", "Sending should clear the draft")
        keep("new-chat-after-send")
        close.tap()
        settle(1.5)

        // New bot, the same sheet, for comparison, through the app's own link.
        app.open(URL(string: "chatwithwork://open?path=/bots/new")!)
        XCTAssertTrue(close.waitForExistence(timeout: 15), "New bot should be the same sheet")
        settle(4)
        keep("new-bot-sheet")
        close.tap()
        settle(1.5)
    }

    // MARK: Steps

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let welcome = app.buttons["welcome.signIn"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 30))
        welcome.tap()
        let email = app.webViews.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 30))
        // The iPad's sheet takes a moment to give the field its keyboard; typed before then, letters go missing.
        email.tap()
        settle(1.5)
        email.typeText(environment["CWW_UI_TEST_EMAIL"] ?? "")
        let password = app.webViews.secureTextFields.firstMatch
        password.tap()
        settle(1.5)
        password.typeText(environment["CWW_UI_TEST_PASSWORD"] ?? "")
        app.webViews.buttons["Sign in"].firstMatch.tap()
        XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 40), "Signing in should land on the home")
        settle(4)
    }

    /// The sheet's composer field, focused: the app's composer that takes
    /// the keyboard, once the page has connected it (the place's own is
    /// under the sheet, out of reach).
    @MainActor
    private func focusSheetField(_ app: XCUIApplication) -> XCUIElement {
        let fields = app.textViews.matching(identifier: "composer.text")
        for _ in 0..<40 {
            for field in fields.allElementsBoundByIndex.reversed() where field.isHittable {
                field.tap()
                settle(0.8)
                if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { return field }
            }
            settle(0.5)
        }
        XCTFail("The sheet's composer never took the keyboard")
        return fields.firstMatch
    }

    @MainActor
    private func sheetButton(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let all = app.buttons.matching(identifier: identifier).allElementsBoundByIndex
        return all.last(where: \.isHittable) ?? all.last ?? app.buttons[identifier]
    }

    @MainActor
    private func openSidebar(_ app: XCUIApplication) {
        let sidebar = app.buttons["shell.sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        settle(1)
        sidebar.tap()
        settle(3)
    }

    @MainActor
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")).firstMatch
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
