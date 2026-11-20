import XCTest

/// The web composer in the app (BridgeRegistry.drawsComposer off), against a
/// Chat with Work server of your own, one case at a time
/// (CWW_UI_TEST_CASE):
///
/// - `keyboard`: New chat from Decisions' bar, in place: the keyboard up
///   before any tap and what's typed landing in the web composer; Send, the
///   keyboard going down as New chat turns into its chat, and staying up
///   after a Send in that chat.
/// - `back`: a chat (CWW_UI_TEST_CHAT, its title in the sidebar; with
///   CWW_UI_TEST_BACK_SEND=1 a question asked first), New chat over it, and
///   Back: where the chat's latest question stands before and after.
/// - `menus`: the composer's + menu and its file picker, the slash menu, the
///   model and permission pickers, in a chat.
/// - `look`: a chat, its composer with the keyboard, and New chat, for the
///   text size, appearance and device runs.
/// - `bar`: Decisions at the end of the bar, New chat on Decisions, and a
///   tap on it from New chat and from a chat.
/// - `sidebar`: the sidebar's New chat and its keyboard.
///
/// With CWW_UI_TEST_HOLD=1 it pauses at named steps (`hold`) for a script
/// outside to look into the page or change how many decisions wait.
///
/// Prints `CWWMARK <event> <seconds since 1970>` at each step and
/// `CWWLOG <what>` for what it found. Needs CWW_UI_TEST_BASE_URL,
/// CWW_UI_TEST_EMAIL and CWW_UI_TEST_PASSWORD (TEST_RUNNER_ prefixed through
/// xcodebuild); skipped without them. Screenshots go to CWW_UI_TEST_SHOTS as
/// well as the result bundle.
final class LocalServerWebComposerTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var step = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(environment["CWW_UI_TEST_PASSWORD"]?.isEmpty != false, "No local server login given")
        try XCTSkipIf(environment["CWW_UI_TEST_CASE"]?.isEmpty != false, "No case given")
    }

    @MainActor
    func testWebComposer() throws {
        let app = XCUIApplication()
        let reset = environment["CWW_UI_TEST_RESET"] != "0"
        app.launchArguments = (reset ? ["-CWWResetState", "YES"] : []) + [
            "-CWWBaseURL", environment["CWW_UI_TEST_BASE_URL"] ?? "http://localhost:3000",
            "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"
        ]
        app.launch()
        if reset { signIn(app) } else { XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 40)) }
        settle(2)
        keep("home")

        switch environment["CWW_UI_TEST_CASE"] {
        case "keyboard": keyboard(app)
        case "back": back(app)
        case "menus": menus(app)
        case "look": look(app)
        case "bar": bar(app)
        case "sidebar": sidebarNewChat(app)
        case "dictate": dictate(app)
        default: XCTFail("Unknown case")
        }
    }

    // MARK: Cases

    @MainActor
    private func keyboard(_ app: XCUIApplication) {
        mark("tap-new-chat")
        app.buttons["shell.newChat"].tap()
        let field = webField(app)
        mark("field-hittable")
        log("keyboard-before-tap \(app.keyboards.firstMatch.exists)")
        keep("new-chat-opened")
        settle(1.5)
        log("keyboard-before-tap-1.5s \(app.keyboards.firstMatch.exists)")
        keep("new-chat-1.5s")

        // The keyboard New chat came up with types into its composer, without a tap.
        if app.keyboards.firstMatch.exists {
            app.typeText("Say hello")
            settle(0.5)
            log("typed-without-tap value=\(webField(app).value as? String ?? "nil")")
            keep("new-chat-typed-without-tap")
            app.typeText(" in five words")
        } else {
            tapUntilKeyboard(app, field)
            webField(app).typeText("Say hello in five words")
        }
        mark("keyboard-up")
        keep("new-chat-keyboard")
        settle(0.5)
        mark("send")
        sendButton(app).tap()
        let question = app.webViews.staticTexts["Say hello in five words"].firstMatch
        _ = question.waitForExistence(timeout: 10)
        mark("question-on-screen")
        followKeyboard(app, "after-new-chat-send", seconds: 6)
        keep("new-chat-sent")
        let titled = NSPredicate(format: "identifier != 'New chat'")
        expectation(for: titled, evaluatedWith: app.navigationBars.firstMatch)
        waitForExpectations(timeout: 40)
        mark("turned-into-chat")
        log("keyboard-after-turn \(app.keyboards.firstMatch.exists)")
        keep("turned-into-chat")
        settle(8)
        log("keyboard-after-turn+8 \(app.keyboards.firstMatch.exists)")
        keep("answer-settled")

        // A Send in the chat.
        if !app.keyboards.firstMatch.exists { tapUntilKeyboard(app, webField(app)) }
        webField(app).typeText("And in three words")
        settle(0.5)
        mark("send-in-chat")
        sendButton(app).tap()
        _ = app.webViews.staticTexts["And in three words"].firstMatch.waitForExistence(timeout: 10)
        mark("question-in-chat-on-screen")
        for wait in [0.3, 1.0, 3.0, 8.0] {
            settle(wait)
            log("keyboard-after-chat-send+\(wait) \(app.keyboards.firstMatch.exists)")
        }
        keep("chat-sent")
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        openChat(app)
        settle(3)
        // A question just asked: its answer short, held under the bar by the room after it.
        if environment["CWW_UI_TEST_BACK_SEND"] == "1" {
            tapUntilKeyboard(app, webField(app))
            webField(app).typeText("Answer in one word")
            sendButton(app).tap()
            settle(10)
        }
        keep("chat-before")
        log("chat-frame-before \(lastQuestionFrame(app))")
        hold("chat-before")
        // A chat's bar ends with Decisions where the server says how many wait: then only a link opens New chat over it.
        guard app.buttons["shell.newChat"].exists else {
            log("no-new-chat-in-a-chat's-bar")
            return
        }
        app.buttons["shell.newChat"].tap()
        _ = app.navigationBars["New chat"].waitForExistence(timeout: 20)
        settle(2)
        keep("new-chat-over-chat")
        hold("new-chat-over-chat")
        backButton(app).tap()
        for (index, wait) in [0.3, 0.7, 2.0].enumerated() {
            settle(wait)
            log("chat-frame-after-\(index) \(lastQuestionFrame(app))")
            keep("chat-after-\(index)")
        }
        hold("chat-after")
    }

    @MainActor
    private func menus(_ app: XCUIApplication) {
        openChat(app)
        settle(2)
        let plus = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == 'Add files and more'")).allElementsBoundByIndex.last(where: \.isHittable)
        if let plus {
            plus.tap()
            settle(1.5)
            keep("plus-menu")
            let attach = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Attach files'")).allElementsBoundByIndex.last(where: \.isHittable)
            log("attach-item \(attach?.label ?? "none")")
            attach?.tap()
            settle(2)
            keep("file-picker")
            log("picker-buttons \(app.buttons.allElementsBoundByIndex.filter(\.isHittable).map(\.label).joined(separator: "|"))")
            log("picker-cells \(app.collectionViews.cells.allElementsBoundByIndex.prefix(8).map(\.label).joined(separator: "|"))")
            // Away from WebKit's menu: what it offers is logged above.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
            settle(1.5)
            keep("after-picker")
        } else {
            log("no-plus-button")
        }

        tapUntilKeyboard(app, webField(app))
        webField(app).typeText("/")
        settle(1.5)
        keep("slash-menu")
        webField(app).typeText(XCUIKeyboardKey.delete.rawValue)
        settle(0.5)

        for label in ["Model", "Choose model", "Permission", "Ask first"] {
            let button = webButton(app, label)
            if button.exists, button.isHittable {
                button.tap()
                settle(1.2)
                keep("picker-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
                settle(1)
            }
        }
        log("composer-buttons \(app.webViews.buttons.allElementsBoundByIndex.filter(\.isHittable).map(\.label).joined(separator: "|"))")
    }

    /// Logs whether the keyboard shows, each time it changes, for `seconds`.
    @MainActor
    private func followKeyboard(_ app: XCUIApplication, _ name: String, seconds: TimeInterval) {
        let start = Date()
        var last: Bool?
        while Date().timeIntervalSince(start) < seconds {
            let shows = app.keyboards.firstMatch.exists
            if shows != last {
                log(String(format: "keyboard-%@ %.2fs %@ title=%@", name, Date().timeIntervalSince(start), shows ? "up" : "down", app.navigationBars.firstMatch.identifier))
                last = shows
            }
            settle(0.1)
        }
    }

    /// Decisions at the end of the bar: New chat on Decisions, Decisions
    /// (with how many wait) everywhere else; a tap goes back to Decisions or
    /// makes it the place. Holds for a script to change how many wait.
    @MainActor
    private func bar(_ app: XCUIApplication) {
        keep("bar-on-decisions")
        log("decisions-has-new-chat \(app.buttons["shell.newChat"].exists)")
        app.buttons["shell.newChat"].tap()
        XCTAssertTrue(app.navigationBars["New chat"].waitForExistence(timeout: 20))
        let decisions = app.buttons["shell.decisions"]
        XCTAssertTrue(decisions.waitForExistence(timeout: 30), "New chat's bar should end with Decisions")
        settle(1)
        keep("bar-on-new-chat")
        log("new-chat-decisions-label \(decisions.label)")
        decisions.tap()
        XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 10), "Decisions should come back")
        settle(1)
        log("after-decisions-tap back=\(backButton(app).exists) stackRootSidebar=\(app.buttons["shell.sidebar"].exists)")
        keep("decisions-again")

        openChat(app)
        XCTAssertTrue(decisions.waitForExistence(timeout: 30), "A chat's bar should end with Decisions")
        settle(1)
        keep("bar-on-chat")
        for count in ["3", "12", "0"] {
            hold("count-\(count)")
            settle(3)
            log("chat-decisions-label-\(count) \(app.buttons["shell.decisions"].firstMatch.label)")
            keep("bar-on-chat-\(count)")
        }
        app.buttons["shell.decisions"].tap()
        XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 10), "Decisions should open from a chat")
        settle(1)
        log("from-chat back=\(backButton(app).exists)")
        keep("decisions-from-chat")
    }

    /// The composer's microphone: iOS asks once for the app, WebKit doesn't
    /// ask again (WebUIController), and the composer records.
    @MainActor
    private func dictate(_ app: XCUIApplication) {
        openChat(app)
        settle(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let mic = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == 'Dictate'")).allElementsBoundByIndex.last(where: \.isHittable)
        XCTAssertNotNil(mic, "The composer should offer dictation")
        mic?.tap()
        settle(1.5)
        keep("dictate-asked")
        log("system-alert \(springboard.alerts.firstMatch.exists ? springboard.alerts.firstMatch.label : "none") app-alert \(app.alerts.firstMatch.exists ? app.alerts.firstMatch.label : "none")")
        for answer in ["Allow", "OK"] where springboard.alerts.buttons[answer].exists {
            springboard.alerts.buttons[answer].tap()
            break
        }
        settle(2)
        log("after-allow app-alert \(app.alerts.firstMatch.exists ? app.alerts.firstMatch.label : "none")")
        keep("dictate-recording")
        log("composer-buttons \(app.webViews.buttons.allElementsBoundByIndex.filter(\.isHittable).map(\.label).suffix(8).joined(separator: "|"))")
    }

    /// The sidebar's New chat: a place, started while the drawer slides, the keyboard once it's shut.
    @MainActor
    private func sidebarNewChat(_ app: XCUIApplication) {
        app.buttons["shell.sidebar"].tap()
        settle(2)
        let link = app.links.matching(NSPredicate(format: "label CONTAINS 'New chat'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        mark("tap-sidebar-new-chat")
        link.tap()
        _ = webField(app)
        mark("field-hittable")
        log("keyboard-after-sidebar-new-chat \(app.keyboards.firstMatch.exists)")
        settle(1.5)
        log("keyboard-after-sidebar-new-chat-1.5s \(app.keyboards.firstMatch.exists)")
        keep("sidebar-new-chat")
    }

    /// With CWW_UI_TEST_HOLD=1, says `name` in a file beside the
    /// screenshots and waits until a script outside removes it (at most a
    /// minute), for it to look into the page or change the server's data.
    @MainActor
    private func hold(_ name: String) {
        guard environment["CWW_UI_TEST_HOLD"] == "1", let folder = environment["CWW_UI_TEST_SHOTS"] else { return }
        let file = URL(fileURLWithPath: folder).appendingPathComponent("hold-\(name)")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        for _ in 0..<600 where FileManager.default.fileExists(atPath: file.path) { settle(0.1) }
    }

    /// The chat as it stands, for the size and appearance runs.
    @MainActor
    private func look(_ app: XCUIApplication) {
        if environment["CWW_UI_TEST_LANDSCAPE"] == "1" { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        openChat(app)
        settle(3)
        keep("chat")
        tapUntilKeyboard(app, webField(app))
        settle(1)
        keep("chat-keyboard")
        // New chat from Decisions' bar: a chat's bar ends with Decisions.
        if app.buttons["shell.decisions"].exists {
            app.buttons["shell.decisions"].tap()
            _ = app.navigationBars["Decisions"].waitForExistence(timeout: 20)
            keep("decisions")
        }
        app.buttons["shell.newChat"].tap()
        _ = app.navigationBars["New chat"].waitForExistence(timeout: 20)
        settle(2)
        keep("new-chat")
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
        settle(1.5)
        email.typeText(environment["CWW_UI_TEST_EMAIL"] ?? "")
        let password = app.webViews.secureTextFields.firstMatch
        password.tap()
        settle(1.5)
        password.typeText(environment["CWW_UI_TEST_PASSWORD"] ?? "")
        app.webViews.buttons["Sign in"].firstMatch.tap()
        XCTAssertTrue(app.buttons["shell.sidebar"].waitForExistence(timeout: 40), "Signing in should land on the home")
        settle(3)
    }

    @MainActor
    private func openChat(_ app: XCUIApplication) {
        let title = environment["CWW_UI_TEST_CHAT"] ?? "Web composer scroll test"
        app.buttons["shell.sidebar"].tap()
        settle(2)
        let row = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(row, "The sidebar should list the chat")
        row?.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 20), "The chat should open")
    }

    /// The web composer's field, once it can be tapped.
    @MainActor
    private func webField(_ app: XCUIApplication) -> XCUIElement {
        let fields = app.webViews.textViews
        for _ in 0..<80 {
            if let field = fields.allElementsBoundByIndex.last(where: \.isHittable) { return field }
            settle(0.1)
        }
        return fields.firstMatch
    }

    /// WebKit doesn't report the web composer's focus to XCUITest; the keyboard says it took the tap.
    @MainActor
    private func tapUntilKeyboard(_ app: XCUIApplication, _ field: XCUIElement) {
        for _ in 0..<10 where !app.keyboards.firstMatch.exists {
            webField(app).tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 1.5)
        }
        XCTAssertTrue(app.keyboards.firstMatch.exists, "The web composer should take the keyboard")
    }

    @MainActor
    private func sendButton(_ app: XCUIApplication) -> XCUIElement {
        webButton(app, "Send")
    }

    @MainActor
    private func webButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let buttons = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label))
        return buttons.allElementsBoundByIndex.last(where: \.isHittable) ?? buttons.firstMatch
    }

    @MainActor
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")).firstMatch
    }

    /// Where the chat's latest question sits on screen, and the bar's bottom.
    @MainActor
    private func lastQuestionFrame(_ app: XCUIApplication) -> String {
        let questions = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Question '")).allElementsBoundByIndex
        let bar = app.navigationBars.firstMatch.frame
        guard let last = questions.last else { return "none bar=\(Int(bar.maxY))" }
        return "\(last.label.prefix(12)) y=\(Int(last.frame.minY)) bar=\(Int(bar.maxY))"
    }

    private func mark(_ event: String) {
        print(String(format: "CWWMARK %@ %.3f", event, Date().timeIntervalSince1970))
    }

    private func log(_ text: String) {
        print("CWWLOG \(text)")
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
