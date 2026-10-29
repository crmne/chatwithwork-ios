import XCTest

/// The signed-in shell, against the contract playground (Playground/server.py)
/// rather than a real server: sign in, the sidebar, a conversation with its
/// native menus, the composer over the keyboard, Bots, Settings, and New chat. Screenshots
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
    func testConnectDialogKeepsDraftOutOfTheWay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", playground, "-CWWAskForNotifications", "NO"]
        app.launch()
        app.buttons["welcome.signIn"].tap()
        let signIn = app.webViews.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()
        let composer = app.textViews["composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        composer.tap()
        composer.typeText("Hello.")
        app.descendants(matching: .any)["Connect"].firstMatch.tap()
        let search = app.webViews.searchFields["Search services"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Google")
        XCTAssertFalse(composer.exists, "The native composer must not cover the web dialog")
        keep("connect-dialog-keyboard")
        app.webViews.buttons["I'm done"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "Hello.")
        keep("connect-dialog-draft-restored")
    }

    @MainActor
    func testSignedInShell() throws {
        let app = XCUIApplication()
        // Notices stay up until tapped away, so the test sees them however
        // long the app takes to settle after a tap.
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", playground, "-CWWToastSeconds", "30", "-CWWAskForNotifications", "NO"]
        app.launch()

        // Signing in opens on a new chat, with the sidebar button and New
        // chat in the bar.
        app.buttons["welcome.signIn"].tap()
        let signIn = app.webViews.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()

        XCTAssertTrue(app.webViews.staticTexts["What are we working on, Carmine?"].waitForExistence(timeout: 20), "Signing in should land on a new chat")
        XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 5), "The sidebar button should be in the bar")
        XCTAssertTrue(app.buttons["shell.newChat"].exists, "New chat should be in the bar")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "No tab bar any more")
        // The server's flash arrives as a native notice.
        let signedIn = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(signedIn.waitForExistence(timeout: 10), "The sign-in flash should show as a toast")
        XCTAssertEqual(signedIn.label, "Signed in.")
        signedIn.tap()
        XCTAssertTrue(signedIn.waitForNonExistence(timeout: 5), "A tap should put the toast away")
        settle()
        keep("new-chat")

        XCTAssertFalse(app.buttons["shell.decisions"].exists, "Decisions is in the sidebar, not the bar")

        // The sidebar: Decisions with what waits, above the switch, then the chats.
        app.buttons["shell.sidebar"].tap()
        let decisions = app.buttons["sidebar.decisions"]
        XCTAssertTrue(decisions.waitForExistence(timeout: 10), "Decisions should lead the sidebar")
        XCTAssertEqual(decisions.value as? String, "2 waiting")
        let switchChats = app.buttons["sidebar.switch.chats"]
        XCTAssertTrue(switchChats.waitForExistence(timeout: 5), "The sidebar should open with its switch")
        XCTAssertLessThan(decisions.frame.minY, switchChats.frame.minY, "Decisions sits just before the switch")
        let instructions = app.buttons["sidebar.instructions"]
        XCTAssertTrue(instructions.exists, "Instructions belongs in the native sidebar as on the web")
        XCTAssertLessThan(app.buttons["sidebar.newChat"].frame.minY, instructions.frame.minY)
        XCTAssertLessThan(instructions.frame.minY, app.textFields["sidebar.search"].frame.minY)
        XCTAssertFalse(app.buttons["sidebar.waiting"].exists, "Decisions is a button, not the old row")
        XCTAssertTrue(app.buttons["Q3 launch commitments for Acme"].waitForExistence(timeout: 5))
        settle(0.8)
        keep("sidebar")

        // Decisions opens its page, and a decision its chat.
        decisions.tap()
        let decision = app.webViews.links.matching(NSPredicate(format: "label CONTAINS %@", "Q3 launch commitments for Acme")).firstMatch
        XCTAssertTrue(decision.waitForExistence(timeout: 20), "Decisions should open its page")
        settle(0.6)
        keep("decisions")
        decision.tap()

        // The chat replaces the root: the sidebar button stays, no back button.
        XCTAssertTrue(app.webViews.staticTexts["What did we promise Acme for the Q3 launch?"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["bridge.menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shell.sidebar"].exists, "A chat is the root, with the sidebar button")
        let overlayComposer = app.descendants(matching: .any)["composer"].firstMatch
        XCTAssertTrue(overlayComposer.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.webViews.firstMatch.frame.maxY, overlayComposer.frame.minY + 50,
                             "The page must draw behind the native composer, including its clear gutters")
        XCTAssertEqual(app.buttons.matching(identifier: "bridge.button").count, 0, "The page's own New chat is left out")
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
        let actions = app.webViews.buttons.matching(identifier: "More actions")
        XCTAssertTrue(actions.firstMatch.waitForExistence(timeout: 10))
        // The latest answer's, on screen above the composer.
        let more = actions.element(boundBy: actions.count - 1)
        more.tap()
        // A tap while the page is still settling can land before the menu's script is ready.
        if !app.buttons["Copy"].waitForExistence(timeout: 5) { more.tap() }
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 5), "The message menu should open")
        app.buttons["Copy"].tap()
        let toast = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "Copying should confirm with a toast")
        XCTAssertEqual(toast.label, "Copied")
        toast.tap()
        XCTAssertTrue(toast.waitForNonExistence(timeout: 5), "A tap should put the toast away")

        // The native composer rides on the keyboard; the web one stays hidden.
        let composer = app.textViews["composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "The app should draw the composer")
        XCTAssertFalse(app.webViews.textViews["Message"].isHittable, "The web composer stays out of sight")
        composer.tap()
        composer.typeText("Draft the recap for Priya")
        XCTAssertTrue(app.buttons["composer.send"].isEnabled)
        settle(1)
        keep("composer-keyboard")

        // Sending goes through the web composer, which posts the question.
        app.buttons["composer.send"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Draft the recap for Priya"].waitForExistence(timeout: 20), "The question should be sent")
        XCTAssertEqual(composer.value as? String ?? "", "", "The field empties once sent")

        // "+" opens the attach sheet.
        app.buttons["composer.plus"].tap()
        // The first time, iOS asks about the photo library for the recent row.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let dontAllow = springboard.alerts.buttons["Don’t Allow"]
        if dontAllow.waitForExistence(timeout: 3) { dontAllow.tap() }
        XCTAssertTrue(app.buttons["attach.files"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["attach.dictate"].exists, "Dictation is in the bar, not the sheet")
        settle(0.8)
        keep("attach-sheet")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(app.buttons["attach.files"].waitForNonExistence(timeout: 5), "A tap above the sheet should put it away")
        settle(0.5)

        // The microphone and the globe are one tap away in the bar.
        let dictate = app.buttons["composer.dictate"]
        let globe = app.buttons["composer.webSearch"]
        XCTAssertTrue(dictate.exists, "The microphone should be in the bar")
        XCTAssertTrue(globe.exists, "The globe should be in the bar")
        XCTAssertEqual(globe.label, "Search the web")
        XCTAssertEqual(globe.value as? String, "Off")
        globe.tap()
        let note = app.staticTexts["composer.lock"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "Turning web search on should say where searches go")
        XCTAssertTrue(note.label.contains("leave the EU"))
        keep("composer-bar")

        // Dictation takes the whole composer while it listens, then gives the words back.
        dictate.tap()
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let line = app.descendants(matching: .any)["composer.dictation"]
        let refused = app.staticTexts["composer.lock"]
        let listening = NSPredicate { _, _ in line.exists || (refused.exists && (refused.label.contains("Dictation couldn't start") || refused.label.contains("needs the microphone"))) }
        expectation(for: listening, evaluatedWith: NSNull())
        waitForExpectations(timeout: 10)
        // A Mac without a microphone (the Mac mini) gives its simulators none: there the app says so
        // and the field stays. ComposerTests covers the line itself.
        if line.exists {
            XCTAssertEqual(line.label, "Listening")
            XCTAssertFalse(composer.exists, "The field steps aside while dictating")
            XCTAssertFalse(dictate.exists, "The bar steps aside too")
            XCTAssertTrue(app.buttons["composer.cancelDictation"].exists)
            settle(1.5)
            keep("dictation-listening")
            app.buttons["composer.send"].tap()
            let dictated = NSPredicate(format: "value CONTAINS %@", "Draft the recap for Priya")
            expectation(for: dictated, evaluatedWith: composer)
            waitForExpectations(timeout: 20)
            XCTAssertFalse(line.exists, "The field comes back with the words")
            keep("dictation-words")
        } else {
            XCTAssertTrue(composer.exists, "Without a microphone the field stays")
        }

        // A swipe from the left edge opens the sidebar; its switch shows the
        // bots in the same skeleton, those that need you first.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        let botsHalf = app.buttons["sidebar.switch.bots"]
        XCTAssertTrue(botsHalf.waitForExistence(timeout: 10), "An edge swipe should open the sidebar")
        XCTAssertEqual(botsHalf.value as? String, "A bot needs you", "The Bots half should carry the attention dot")
        botsHalf.tap()
        XCTAssertTrue(app.buttons["sidebar.botsCard"].waitForExistence(timeout: 5), "The Bots card should take the list switcher's place")
        XCTAssertTrue(app.buttons["sidebar.newBot"].exists, "New bot should sit where New chat does")
        XCTAssertFalse(app.buttons["sidebar.newChat"].exists)
        let botRows = app.buttons.matching(identifier: "sidebar.bot")
        XCTAssertEqual(botRows.count, 3)
        XCTAssertEqual(botRows.element(boundBy: 0).label, "Front desk, shared in Acme launch", "Bots that need you come first")
        XCTAssertTrue(app.staticTexts["Needs you"].exists && app.staticTexts["Quiet"].exists)
        settle(0.8)
        keep("sidebar-bots")

        // A bot's row opens its page over the chat.
        app.buttons["Monday Drive digest"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Every Monday at 8:30, tells you what changed in Drive."].waitForExistence(timeout: 20), "A bot should open from its row")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The card opens the Bots page.
        app.buttons["shell.sidebar"].tap()
        let card = app.buttons["sidebar.botsCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The sidebar should keep the Bots half")
        card.tap()
        XCTAssertTrue(app.webViews.staticTexts["Monday Drive digest"].waitForExistence(timeout: 20), "Bots should open from the sidebar")
        settle()
        keep("bots")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Back to the chats for the rest.
        app.buttons["shell.sidebar"].tap()
        let chatsHalf = app.buttons["sidebar.switch.chats"]
        XCTAssertTrue(chatsHalf.waitForExistence(timeout: 10))
        chatsHalf.tap()
        XCTAssertTrue(app.buttons["sidebar.newChat"].waitForExistence(timeout: 5), "Chats should come back")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        settle(0.5)

        // Settings, from the person at the sidebar's foot, comes up as a sheet.
        app.buttons["shell.sidebar"].tap()
        let person = app.buttons["sidebar.person"]
        XCTAssertTrue(person.waitForExistence(timeout: 10))
        person.tap()
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["Connectors"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["sheet.close"].exists, "Settings should be a sheet")
        settle()
        keep("settings")
        app.buttons["sheet.close"].tap()

        // New chat from the bar replaces the chat.
        app.buttons["shell.newChat"].tap()
        XCTAssertTrue(app.webViews.staticTexts["What are we working on, Carmine?"].waitForExistence(timeout: 20))

        // Text shared into the app (the share extension's link) waits in a
        // new chat's composer, never sent by itself.
        openAppLink(app, "chatwithwork://new-chat?text=Read%20this%20before%20Monday&url=https%3A%2F%2Fexample.com%2Fplan")
        let filled = NSPredicate(format: "value CONTAINS %@", "Read this before Monday")
        expectation(for: filled, evaluatedWith: app.textViews["composer.text"])
        waitForExpectations(timeout: 20)
        keep("shared-text")

        // A chat still answering, opened from a Live Activity's link: Stop in
        // the composer. Leaving the app starts its Live Activity.
        openAppLink(app, "chatwithwork://open?path=/1000001/chats/41")
        let stop = app.buttons["composer.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 20), "A working chat should show Stop")
        XCTAssertEqual(stop.label, "Stop response")
        XCTAssertFalse(app.buttons["composer.send"].exists, "Stop stands alone while the field is empty")
        settle()
        keep("working-chat")

        // Words bring Send beside Stop, to steer; an empty field leaves Stop alone.
        let field = app.textViews["composer.text"]
        field.tap()
        field.typeText("Shorter")
        XCTAssertTrue(app.buttons["composer.send"].waitForExistence(timeout: 5), "Words should bring Send beside Stop")
        XCTAssertTrue(stop.exists, "Stop stays beside Send")
        settle(0.5)
        keep("working-chat-steer")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        XCTAssertTrue(app.buttons["composer.send"].waitForNonExistence(timeout: 5), "An empty field should leave Stop alone again")
        XCUIDevice.shared.press(.home)
        settle(3)
        keep("live-activity")
    }

    /// The app offers notifications once, the first time a change waits for
    /// the person (or an answer takes a while), never right after signing
    /// in: its own explanation, then iOS's prompt. Launching again doesn't
    /// offer them again. iOS remembers its answer across reinstalls, so this
    /// needs a simulator that was never asked (`xcrun simctl erase <udid>` first).
    @MainActor
    func testOffersNotificationsWhenAChangeWaits() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", playground]
        app.launch()

        app.buttons["welcome.signIn"].tap()
        let signIn = app.webViews.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()

        let prompt = app.alerts["Want a nudge when it's ready?"]
        XCTAssertFalse(prompt.waitForExistence(timeout: 6), "Signing in alone shouldn't offer notifications")

        // Chat 42 waits for an approval.
        openChat(app, titled: "Q3 launch commitments for Acme")
        // A freshly erased simulator takes a while to answer its first
        // question about notification settings.
        XCTAssertTrue(prompt.waitForExistence(timeout: 60), "A change waiting should offer notifications")
        keep("notifications-prompt")
        prompt.buttons["Continue"].tap()

        // iOS's own prompt belongs to SpringBoard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "Continue should lead to iOS's prompt")
        allow.tap()

        // Launched again, signed in: no second offer.
        app.terminate()
        app.launchArguments = ["-CWWBaseURL", playground]
        app.launch()
        openChat(app, titled: "Q3 launch commitments for Acme")
        XCTAssertFalse(prompt.waitForExistence(timeout: 6), "The app offers notifications only once")
    }

    /// A file the assistant made opens in its viewer, full screen over the
    /// chat: its slides, the file's name for a title, and Share in the bar,
    /// which asks which file (the deck or the PDF of its slides) and hands
    /// the file itself to the share sheet.
    @MainActor
    func testFileViewer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", playground, "-CWWAskForNotifications", "NO"]
        app.launch()

        app.buttons["welcome.signIn"].tap()
        let signIn = app.webViews.buttons["Sign in"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()
        openChat(app, titled: "Q3 launch commitments for Acme")

        let chip = app.webViews.links["Preview board-update.pptx, 52 KB"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "The answer's file should be a chip")
        chip.tap()

        XCTAssertTrue(app.navigationBars["board-update.pptx"].waitForExistence(timeout: 20), "The viewer should be titled with the file's name")
        // WebKit names a picture by its alt text, as an image or (an SVG's) a group.
        XCTAssertTrue(app.webViews.descendants(matching: .any)["Slide 1"].waitForExistence(timeout: 10), "The viewer should show the slides")
        let share = app.buttons["bridge.file"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Share should be in the bar")
        XCTAssertTrue(app.buttons["sheet.close"].exists, "The viewer should close like a sheet")
        XCTAssertFalse(app.webViews.links["Download board-update.pptx"].exists, "The page's own bar is left out")
        settle()
        keep("file-viewer")

        share.tap()
        XCTAssertTrue(app.buttons["PDF"].waitForExistence(timeout: 5), "Share should ask which file")
        XCTAssertTrue(app.buttons["PowerPoint"].exists)
        settle(0.6)
        keep("file-share-menu")
        app.buttons["PDF"].tap()

        // The share sheet runs out of process; its Copy action is one of its own.
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 20), "The share sheet should open with the file")
        settle()
        keep("file-share-sheet")
        // A tap outside puts it away: iOS shows it as a card under the button,
        // or as a sheet from the bottom.
        let card = app.otherElements["ShareSheet.RemoteContainerView"]
        let below = !card.exists || card.frame.midY < app.frame.midY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.9 : 0.05)).tap()
        XCTAssertTrue(copy.waitForNonExistence(timeout: 10), "A tap outside the share sheet should put it away")

        // Two fingers zoom in on the slides, and the file opens whole again.
        settle()
        let slide = app.webViews.descendants(matching: .any)["Slide 1"]
        let whole = slide.frame.width
        slide.pinch(withScale: 2.5, velocity: 1.5)
        XCTAssertTrue(eventually { slide.frame.width > whole * 1.5 }, "Two fingers should zoom in on the slides")
        keep("file-zoomed")
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "Closing should go back to the chat")
        chip.tap()
        XCTAssertTrue(app.navigationBars["board-update.pptx"].waitForExistence(timeout: 20))
        XCTAssertTrue(eventually { abs(slide.frame.width - whole) < 2 }, "The file should open whole again")
        app.buttons["sheet.close"].tap()
    }

    /// Whether a condition holds within a few seconds, as the accessibility
    /// tree catches up with a gesture.
    @MainActor
    private func eventually(_ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            if condition() { return true }
            settle(0.25)
        }
        return condition()
    }

    /// Opens one of the app's own links, as a widget or the share extension
    /// would; iOS asks first when it comes from outside.
    @MainActor
    private func openAppLink(_ app: XCUIApplication, _ link: String) {
        // Through the system, as a widget's tap does: XCUIApplication.open
        // would launch the app again without its launch arguments.
        XCUIDevice.shared.system.open(URL(string: link)!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 10) { open.tap() }
    }

    /// Opens a chat from the sidebar.
    @MainActor
    private func openChat(_ app: XCUIApplication, titled title: String) {
        let sidebar = app.buttons["shell.sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 20))
        sidebar.tap()
        let row = app.buttons[title]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
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
