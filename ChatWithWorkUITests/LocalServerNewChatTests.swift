import XCTest

/// New chat and New bot as pages (path configuration v4), against a Chat with
/// Work server of your own: the app starts on Decisions; the bar's New chat
/// pushes New chat over it with Back and the keyboard up; Back keeps what was
/// typed for the next New chat; the sidebar's New chat is a place, the root;
/// sending turns it into the chat where it stands, the root still, with no
/// back; New chat over a chat comes back to that chat; New bot from Bots is a
/// page too.
///
/// `testMeasure` walks one case at a time for the before and after videos
/// (CWW_UI_TEST_CASE: sidebar, decisions, bots, chat, rotate, offline,
/// lost, suggestions, web),
/// printing `CWWMARK <event> <seconds since 1970>` at each tap, and works on
/// builds where New chat is a sheet too, to compare.
///
/// Needs a development server reachable from the simulator and a login:
/// CWW_UI_TEST_BASE_URL, CWW_UI_TEST_EMAIL and CWW_UI_TEST_PASSWORD, and
/// the organization's id as CWW_UI_TEST_ACCOUNT (TEST_RUNNER_ prefixed
/// through xcodebuild). Skipped without them. Each
/// send starts a chat. Screenshots go to CWW_UI_TEST_SHOTS as well as the
/// result bundle, numbered in walk order.
final class LocalServerNewChatTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(environment["CWW_UI_TEST_PASSWORD"]?.isEmpty != false, "No local server login given")
    }

    @MainActor
    func testNewChatIsAPage() throws {
        try XCTSkipIf(environment["CWW_UI_TEST_CASE"]?.isEmpty == false, "Measuring a case instead")
        let app = launch(reset: true)
        signIn(app)
        keep("home")
        XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 20), "The app should start on Decisions")

        // The bar's New chat: pushed over Decisions, with Back, the keyboard up, no sheet.
        let newChat = app.buttons["shell.newChat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 10))
        newChat.tap()
        XCTAssertTrue(app.navigationBars["New chat"].waitForExistence(timeout: 20), "New chat should open as a page")
        XCTAssertFalse(app.buttons["sheet.close"].exists, "New chat isn't a sheet")
        XCTAssertTrue(backButton(app).waitForExistence(timeout: 5), "New chat from the bar has Back to Decisions")
        var field = composerField(app)
        let native = drawsComposer(app)
        if native {
            XCTAssertTrue(waitForFocus(field), "New chat opened by a tap takes the keyboard")
        } else {
            field.tap()
            settle(1)
        }
        keep("new-chat-pushed")

        field.typeText("Draft that should stay")
        settle(1)
        backButton(app).tap()
        XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 10), "Back should return to Decisions")
        keep("back-to-decisions")

        // The sidebar's New chat: a place, the root, with the words left in it.
        openSidebar(app)
        tapSidebarNewChat(app)
        XCTAssertTrue(app.navigationBars["New chat"].waitForExistence(timeout: 20))
        settle(2)
        XCTAssertTrue(app.buttons["shell.sidebar"].exists, "The sidebar's New chat is a place, with the sidebar button")
        XCTAssertFalse(backButton(app).exists, "A place has no back")
        field = composerField(app)
        if native {
            XCTAssertEqual(field.value as? String, "Draft that should stay", "New chat should open with the words left in it")
        } else {
            // The web composer keeps no draft for a chat that doesn't exist yet.
            field.tap()
            settle(1)
            if (field.value as? String)?.contains("Draft that should stay") != true { field.typeText("Draft that should stay") }
        }
        keep("sidebar-new-chat")

        // Send: the page turns into the chat where it stands, the root still.
        sendButton(app).tap()
        let question = app.webViews.staticTexts["Draft that should stay"].firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5), "The question should be on screen at once")
        keep("sent")
        let titled = NSPredicate(format: "identifier != 'New chat'")
        expectation(for: titled, evaluatedWith: app.navigationBars.firstMatch)
        waitForExpectations(timeout: 40)
        settle(2)
        XCTAssertTrue(app.buttons["shell.sidebar"].exists, "The chat is the root, with the sidebar button")
        XCTAssertFalse(backButton(app).exists, "The chat has no back")
        let chatTitle = app.navigationBars.firstMatch.identifier
        keep("chat")

        // New chat over that chat: pushed, empty (Send cleared the draft), and Back returns to the chat.
        newChat.tap()
        XCTAssertTrue(app.navigationBars["New chat"].waitForExistence(timeout: 20))
        field = composerField(app)
        XCTAssertNotEqual(field.value as? String, "Draft that should stay", "Sending should clear the draft")
        XCTAssertTrue(backButton(app).exists)
        // The bar's New chat on New chat focuses it rather than stacking another.
        newChat.tap()
        settle(1.5)
        XCTAssertTrue(backButton(app).exists)
        backButton(app).tap()
        XCTAssertTrue(app.navigationBars[chatTitle].waitForExistence(timeout: 10), "Back should return to the chat New chat was opened from")
        XCTAssertFalse(backButton(app).exists, "and that chat is the root")
        keep("back-to-chat")

        // New bot from Bots: a page pushed over Bots.
        openBots(app)
        let newBot = app.buttons.matching(NSPredicate(format: "identifier == 'bridge.button' AND label == 'New bot'")).firstMatch
        XCTAssertTrue(newBot.waitForExistence(timeout: 20), "Bots should offer New bot in the bar")
        newBot.tap()
        XCTAssertTrue(app.navigationBars["New bot"].waitForExistence(timeout: 20), "New bot should open as a page")
        XCTAssertFalse(app.buttons["sheet.close"].exists, "New bot isn't a sheet")
        XCTAssertTrue(backButton(app).exists, "New bot from Bots has Back")
        settle(2)
        keep("new-bot")
        backButton(app).tap()
        XCTAssertTrue(app.navigationBars["Bots"].waitForExistence(timeout: 10))
    }

    // MARK: Measuring

    /// One case, for the videos: every tap and send is marked with the time.
    @MainActor
    func testMeasure() throws {
        let name = environment["CWW_UI_TEST_CASE"] ?? ""
        try XCTSkipIf(name.isEmpty, "Set CWW_UI_TEST_CASE to measure a case")
        // Signed in already where a run before left the app so: the server throttles sign-ins in quick succession.
        var app = launch(reset: environment["CWW_UI_TEST_RESET"] == "1")
        if app.buttons["welcome.signIn"].waitForExistence(timeout: 15) { signIn(app) }
        settle(2)
        mark("signed-in")

        switch name {
        case "sidebar":
            // Two launches, each a cold New chat and then warm ones.
            for launchIndex in 1...2 {
                if launchIndex == 2 {
                    app.terminate()
                    app = launch(reset: false)
                    XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 40))
                    settle(4)
                    mark("relaunched")
                }
                for run in 1...(launchIndex == 1 ? 4 : 2) {
                    openSidebar(app)
                    mark("tap-\(run == 1 ? "cold" : "warm")-\(launchIndex)-\(run)")
                    tapSidebarNewChat(app)
                    send(app, "In one short sentence, which planet is largest?")
                    settle(12)
                }
            }
        case "lost":
            // Six sends from the sidebar's New chat, each a fresh question, to count answers that never show.
            let questions = ["In one short sentence, which ocean is deepest?", "In one short sentence, which metal is lightest?",
                             "In one short sentence, which bird is fastest?", "In one short sentence, which tree is tallest?",
                             "In one short sentence, which mountain is highest?", "In one short sentence, which desert is largest?"]
            for (run, question) in questions.enumerated() {
                openSidebar(app)
                mark("tap-lost-\(run + 1)")
                tapSidebarNewChat(app)
                send(app, question)
                settle(30)
                keep("lost-\(run + 1)")
            }
        case "decisions":
            for run in 1...2 {
                // Back from the turn lands on Decisions again for the next run; where the chat took the root (New
                // chat as a sheet), the sidebar opens it.
                if run > 1, !app.navigationBars["Decisions"].waitForExistence(timeout: 3) { openPlace(app, "Decisions") }
                XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 20))
                settle(2)
                mark("tap-decisions-\(run)")
                app.buttons["shell.newChat"].tap()
                send(app, "In one short sentence, what colour is the sky?")
                settle(10)
                mark("back-\(run)")
                tapBack(app)
                settle(3)
                keep("decisions-back-\(run)")
            }
        case "bots":
            for run in 1...2 {
                openBots(app)
                let newBot = app.buttons.matching(NSPredicate(format: "identifier == 'bridge.button' AND label == 'New bot'")).firstMatch
                XCTAssertTrue(newBot.waitForExistence(timeout: 20))
                settle(2)
                mark("tap-bots-\(run)")
                newBot.tap()
                send(app, "Every weekday at 9, tell me the weather in Berlin.")
                settle(12)
                mark("back-\(run)")
                tapBack(app)
                settle(3)
                keep("bots-back-\(run)")
            }
        case "chat":
            // A chat to start from, opened from the sidebar.
            openSidebar(app)
            tapSidebarNewChat(app)
            send(app, "In one short sentence, say hello.")
            settle(10)
            for run in 1...2 {
                mark("tap-chat-\(run)")
                app.buttons["shell.newChat"].tap()
                send(app, "In one short sentence, which fruit is yellow?")
                settle(10)
                mark("back-\(run)")
                tapBack(app)
                settle(3)
                keep("chat-back-\(run)")
            }
        case "rotate":
            app.buttons["shell.newChat"].tap()
            let field = composerField(app)
            XCTAssertTrue(field.waitForExistence(timeout: 20))
            settle(2)
            mark("rotate-landscape")
            XCUIDevice.shared.orientation = .landscapeLeft
            settle(3)
            keep("new-chat-landscape")
            mark("rotate-portrait")
            XCUIDevice.shared.orientation = .portrait
            settle(3)
            send(app, "In one short sentence, which river is longest?", tapField: true)
            settle(0.6)
            mark("rotate-after-turn")
            XCUIDevice.shared.orientation = .landscapeLeft
            settle(4)
            keep("chat-landscape")
            XCUIDevice.shared.orientation = .portrait
            settle(4)
            keep("chat-portrait")
        case "suggestions":
            // A suggestion's words land in the app's field (with the keyboard where the build reads fill), on New
            // chat and on Decisions' All clear; then one of New bot's examples, which sends itself.
            for place in ["new-chat", "decisions"] {
                if place == "new-chat" {
                    app.buttons["shell.newChat"].tap()
                    XCTAssertTrue(app.navigationBars["New chat"].waitForExistence(timeout: 20))
                } else {
                    tapBack(app)
                    if !app.navigationBars["Decisions"].waitForExistence(timeout: 5) { openPlace(app, "Decisions") }
                }
                let field = composerField(app)
                XCTAssertTrue(field.waitForExistence(timeout: 20))
                settle(2)
                if place == "new-chat", field.elementType == .textView, field.identifier == "composer.text" {
                    if !waitForFocus(field, timeout: 2) { field.tap() }
                    if waitForFocus(field, timeout: 5) { field.typeText("A draft the suggestion replaces") }
                }
                app.swipeDown()
                settle(1)
                let suggestion = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'week' OR label CONTAINS[c] 'notes' OR label CONTAINS[c] 'help'")).allElementsBoundByIndex.first(where: \.isHittable)
                XCTAssertNotNil(suggestion, "\(place) should offer suggestions")
                mark("suggestion-\(place)")
                suggestion?.tap()
                settle(2.5)
                keep("suggestion-\(place)")
                let value = composerField(app).value as? String ?? ""
                let focused = (composerField(app).value(forKey: "hasKeyboardFocus") as? Bool) == true
                print("CWWRESULT suggestion-\(place) text=\(value.replacingOccurrences(of: "\n", with: " ")) focused=\(focused)")
                XCTAssertFalse(value.isEmpty || value == "A draft the suggestion replaces", "The suggestion's words should be in the field")
            }
            // New bot's examples send their sentence themselves.
            openBots(app)
            let newBot = app.buttons.matching(NSPredicate(format: "identifier == 'bridge.button' AND label == 'New bot'")).firstMatch
            XCTAssertTrue(newBot.waitForExistence(timeout: 20))
            newBot.tap()
            XCTAssertTrue(app.navigationBars["New bot"].waitForExistence(timeout: 20))
            settle(3)
            keep("new-bot-examples")
            let example = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Every' OR label BEGINSWITH[c] 'When' OR label BEGINSWITH[c] 'Each'")).allElementsBoundByIndex.first(where: \.isHittable)
            XCTAssertNotNil(example, "New bot should offer examples")
            mark("example")
            example?.tap()
            settle(1)
            keep("new-bot-example-sent")
            settle(8)
            keep("new-bot-example-chat")
            print("CWWRESULT example title=\(app.navigationBars.firstMatch.identifier) back=\(backButton(app).exists)")
            tapBack(app)
            settle(3)
            keep("new-bot-example-back")
            print("CWWRESULT example-back title=\(app.navigationBars.firstMatch.identifier)")
        case "web":
            // The web composer, where the app doesn't draw its own (BridgeRegistry.drawsComposer).
            XCTAssertFalse(app.textViews["composer.text"].exists, "No native composer")
            mark("tap-web-1")
            app.buttons["shell.newChat"].tap()
            XCTAssertTrue(app.navigationBars["New chat"].waitForExistence(timeout: 20))
            settle(3)
            keep("web-new-chat")
            let field = app.webViews.textViews.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10), "The web composer's field")
            mark("composer")
            field.tap()
            settle(1.5)
            field.typeText("In one short sentence, which planet is smallest?")
            settle(1)
            keep("web-typing-keyboard")
            mark("send")
            webButton(app, "Send").tap()
            settle(0.4)
            keep("web-sent-at-once")
            settle(8)
            keep("web-chat-answered")
            mark("chat-keyboard-open")
            app.webViews.textViews.firstMatch.tap()
            settle(1.5)
            keep("web-chat-keyboard-open")
            mark("chat-keyboard-close")
            app.swipeDown()
            settle(1.5)
            keep("web-chat-keyboard-closed")
            // Suggestions on New chat and on Decisions' All clear.
            app.buttons["shell.newChat"].tap()
            XCTAssertTrue(app.navigationBars["New chat"].waitForExistence(timeout: 20))
            settle(3)
            if let suggestion = suggestionButton(app) {
                mark("suggestion-new-chat")
                suggestion.tap()
                settle(2)
                keep("web-suggestion-new-chat")
                print("CWWRESULT web-suggestion-new-chat \(String(describing: app.webViews.textViews.firstMatch.value))")
            }
            tapBack(app)
            settle(1)
            openPlace(app, "Decisions")
            settle(3)
            keep("web-decisions-all-clear")
            if let suggestion = suggestionButton(app) {
                mark("suggestion-decisions")
                suggestion.tap()
                settle(2)
                keep("web-suggestion-decisions")
                print("CWWRESULT web-suggestion-decisions \(String(describing: app.webViews.textViews.firstMatch.value))")
            }
        case "offline":
            app.buttons["shell.newChat"].tap()
            XCTAssertTrue(composerField(app).waitForExistence(timeout: 20))
            settle(3)
            let flag = try XCTUnwrap(environment["CWW_UI_TEST_OFFLINE_FLAG"], "Needs the proxy's offline flag file")
            FileManager.default.createFile(atPath: flag, contents: Data())
            mark("offline")
            settle(1)
            send(app, "This should come back to the field.")
            settle(8)
            let field = composerField(app)
            keep("offline-refused")
            XCTAssertEqual(field.value as? String, "This should come back to the field.", "The words should come back to the field")
            try? FileManager.default.removeItem(atPath: flag)
            mark("online")
            settle(3)
        default:
            XCTFail("Unknown case \(name)")
        }
        mark("done")
    }

    /// Types `question` into the composer that takes the keyboard and sends it, marking the send.
    @MainActor
    private func send(_ app: XCUIApplication, _ question: String, tapField: Bool = false) {
        let field = composerField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 30), "New chat should show its composer")
        mark("composer")
        let native = field.identifier == "composer.text"
        if native {
            if tapField || !waitForFocus(field, timeout: 3) {
                field.tap()
                XCTAssertTrue(waitForFocus(field))
            }
        } else {
            // WebKit doesn't report the web composer's focus to XCUITest; the keyboard says it took the tap (a tap
            // while the page's skeleton still covers it lands on the skeleton).
            for _ in 0..<10 where !app.keyboards.firstMatch.exists {
                composerField(app).tap()
                _ = app.keyboards.firstMatch.waitForExistence(timeout: 1.5)
            }
            XCTAssertTrue(app.keyboards.firstMatch.exists, "The web composer should take the keyboard")
        }
        (native ? field : composerField(app)).typeText(question)
        settle(1.5)
        let send = sendButton(app)
        mark("send")
        send.tap()
    }

    // MARK: Steps

    @MainActor
    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-CWWResetState", "YES"] : []) + [
            "-CWWBaseURL", environment["CWW_UI_TEST_BASE_URL"] ?? "http://localhost:3000",
            "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"
        ]
        app.launch()
        return app
    }

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

    /// The app's composer field on top: the last one that can be reached
    /// (a sheet's, where New chat is one, over the place's own).
    @MainActor
    private func composerField(_ app: XCUIApplication) -> XCUIElement {
        let fields = app.textViews.matching(identifier: "composer.text")
        let web = app.webViews.textViews
        for _ in 0..<60 {
            if let field = fields.allElementsBoundByIndex.last(where: \.isHittable) { return field }
            // The web composer, where the app doesn't draw its own.
            if !fields.firstMatch.exists, let field = web.allElementsBoundByIndex.first(where: \.isHittable) { return field }
            settle(0.25)
        }
        return fields.firstMatch.exists ? fields.firstMatch : web.firstMatch
    }

    /// Whether the app draws the composer (BridgeRegistry.drawsComposer) on the page on screen.
    @MainActor
    private func drawsComposer(_ app: XCUIApplication) -> Bool {
        app.textViews["composer.text"].waitForExistence(timeout: 3)
    }

    @MainActor
    private func sendButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "composer.send").allElementsBoundByIndex.last(where: \.isHittable) ?? webButton(app, "Send")
    }

    @MainActor
    private func waitForFocus(_ field: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if field.exists, (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
            settle(0.2)
        }
        return false
    }

    @MainActor
    private func openSidebar(_ app: XCUIApplication) {
        let sidebar = app.buttons["shell.sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        settle(1)
        sidebar.tap()
        settle(2)
    }

    /// The sidebar page's New chat, or the native sidebar's.
    @MainActor
    private func tapSidebarNewChat(_ app: XCUIApplication) {
        let link = app.links.matching(NSPredicate(format: "label CONTAINS 'New chat'")).firstMatch
        if link.waitForExistence(timeout: 20) {
            link.tap()
        } else {
            app.buttons["sidebar.newChat"].tap()
        }
    }

    /// A place from the sidebar page: Decisions is a link; Bots is Recent's
    /// filter, whose option chosen again opens its page. (Not the app's own
    /// link: XCUITest relaunches the app for it, without its launch arguments.)
    @MainActor
    private func openPlace(_ app: XCUIApplication, _ name: String) {
        let bar = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS %@", name)).firstMatch
        if bar.exists, app.buttons["shell.sidebar"].exists { return }
        openSidebar(app)
        let page = app.webViews.descendants(matching: .any)
        let named = page.matching(NSPredicate(format: "label == %@", name)).allElementsBoundByIndex
        for _ in 0..<3 where !bar.exists {
            guard let target = named.first(where: { $0.exists && $0.isHittable }) ?? page.matching(NSPredicate(format: "label == %@", name)).allElementsBoundByIndex.first(where: \.isHittable)
            else { settle(1); continue }
            target.tap()
            _ = bar.waitForExistence(timeout: 3)
        }
        if !bar.waitForExistence(timeout: 15) { keep("no-\(name.lowercased())") }
        XCTAssertTrue(bar.exists, "\(name) should open")
    }

    @MainActor
    private func openBots(_ app: XCUIApplication) {
        openPlace(app, "Bots")
        settle(2)
    }

    /// Back, or a sheet's close where New chat is one.
    @MainActor
    private func tapBack(_ app: XCUIApplication) {
        if backButton(app).exists {
            backButton(app).tap()
        } else if app.buttons["sheet.close"].exists {
            app.buttons["sheet.close"].tap()
        }
    }

    @MainActor
    private func webButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let buttons = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label))
        return buttons.allElementsBoundByIndex.last(where: \.isHittable) ?? buttons.firstMatch
    }

    @MainActor
    private func suggestionButton(_ app: XCUIApplication) -> XCUIElement? {
        app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'week' OR label CONTAINS[c] 'notes' OR label CONTAINS[c] 'help'"))
            .allElementsBoundByIndex.first(where: \.isHittable)
    }

    @MainActor
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")).firstMatch
    }

    private func mark(_ event: String) {
        print(String(format: "CWWMARK %@ %.3f", event, Date().timeIntervalSince1970))
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
