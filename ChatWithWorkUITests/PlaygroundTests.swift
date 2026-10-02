import XCTest

/// The signed-in shell, against the contract playground (Playground/server.py)
/// rather than a real server: sign in, the tabs, a conversation with its
/// native menus, the composer over the keyboard, and New chat. Screenshots
/// are kept as attachments in the result bundle.
///
/// Start the playground first, then run with the ChatWithWorkUITests scheme
/// and CWW_UI_TEST_PLAYGROUND (default http://localhost:8765). Skipped when
/// the playground isn't running.
final class PlaygroundTests: XCTestCase {
    private var playground: String {
        ProcessInfo.processInfo.environment["CWW_UI_TEST_PLAYGROUND"] ?? "http://localhost:8765"
    }

    /// Appended to screenshot names, so light and dark runs don't collide.
    private var suffix: String {
        ProcessInfo.processInfo.environment["CWW_UI_TEST_APPEARANCE"].map { "-\($0)" } ?? ""
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        let reachable = (try? Data(contentsOf: URL(string: "\(playground)/users/sign_in")!)) != nil
        try XCTSkipUnless(reachable, "The playground isn't running at \(playground)")
    }

    @MainActor
    func testSignedInShell() throws {
        let app = XCUIApplication()
        // Notices stay up until tapped away, so the test sees them however
        // long the app takes to settle after a tap.
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", playground, "-CWWToastSeconds", "30"]
        app.launch()

        // Signing in rebuilds the shell on the Chats tab.
        app.buttons["welcome.signIn"].tap()
        let signIn = app.webViews.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()

        let chat = app.webViews.staticTexts["Q3 launch commitments for Acme"]
        XCTAssertTrue(chat.waitForExistence(timeout: 20), "Signing in should land on the chat list")
        XCTAssertTrue(app.buttons["bridge.button"].waitForExistence(timeout: 5), "New chat should be in the navigation bar")
        // The server's flash arrives as a native notice.
        let signedIn = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(signedIn.waitForExistence(timeout: 10), "The sign-in flash should show as a toast")
        XCTAssertEqual(signedIn.label, "Signed in.")
        settle()
        keep("chats")
        signedIn.tap()
        XCTAssertTrue(signedIn.waitForNonExistence(timeout: 5), "A tap should put the toast away")

        // A conversation, with New chat and the chat's menu in the bar.
        chat.tap()
        XCTAssertTrue(app.webViews.staticTexts["What did we promise Acme for the Q3 launch?"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["bridge.menu"].waitForExistence(timeout: 5))
        settle()
        keep("chat")

        app.buttons["bridge.menu"].tap()
        XCTAssertTrue(app.buttons["Move to project"].waitForExistence(timeout: 5))
        settle(0.6)
        keep("chat-menu")
        // A form in a sheet: close on the leading side, its submit on the trailing.
        app.buttons["Move to project"].firstMatch.tap()
        XCTAssertTrue(app.buttons["bridge.form"].waitForExistence(timeout: 20), "The form's submit should move to the navigation bar")
        XCTAssertTrue(app.buttons["sheet.close"].exists)
        settle()
        keep("move-sheet")
        app.buttons["sheet.close"].tap()

        // A message's actions in one native menu.
        let more = app.webViews.buttons["More actions"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5), "The message menu should open")
        settle(0.6)
        keep("message-menu")

        // Copying confirms with a notice, which a tap puts away.
        app.buttons["Copy"].tap()
        let toast = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "Copying should confirm with a toast")
        XCTAssertEqual(toast.label, "Copied")
        keep("copied-toast")
        toast.tap()
        XCTAssertTrue(toast.waitForNonExistence(timeout: 5), "A tap should put the toast away")

        // The composer rides on the keyboard.
        let composer = app.webViews.textViews["Message"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Draft the recap for Priya")
        settle(1)
        keep("composer-keyboard")

        // Delete asks natively.
        app.swipeDown()
        app.buttons["bridge.menu"].tap()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.alerts.buttons["Delete"].waitForExistence(timeout: 5), "Deleting should ask with a native alert")
        settle(0.5)
        keep("delete-alert")
        app.alerts.buttons["Cancel"].tap()

        // The other tabs.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Acme launch"].waitForExistence(timeout: 20))
        settle()
        keep("projects")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Connectors"].waitForExistence(timeout: 20))
        settle()
        keep("settings")

        // New chat opens as a sheet over Chats.
        app.tabBars.buttons["New chat"].tap()
        XCTAssertTrue(app.webViews.staticTexts["What are we working on, Carmine?"].waitForExistence(timeout: 20))
        settle()
        keep("new-chat")
    }

    private func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func keep(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "playground-\(name)\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
