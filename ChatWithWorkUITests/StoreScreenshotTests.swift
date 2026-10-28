import UIKit
import XCTest

/// The App Store screenshots, taken from the app against a real server with
/// the listings' synthetic demo, Northwind Studio: its people, clients, bots
/// and every message are made up. crmne/films' `chatwithwork/store-screenshots`
/// seeds it on a server of its own whose clock reads 9:41 (staging's
/// screenshot account, from the Rails app's `script/store/seed`, has no bots
/// yet). It walks the sidebar shell as Ana would and keeps each screen as an
/// attachment named `store-<n>-<screen>`, which `script/screenshots` exports
/// from the result bundle, and as `<n>-<screen>.png` in the folder named by
/// CWW_SCREENSHOT_SHOTS, where given (result bundles drop attachments on
/// iPad simulators).
///
/// It only opens, scrolls and looks. It never presses anything that posts
/// (Approve, Deny, Send, Skip, Snooze, a model in the picker), so the demo's
/// decisions still wait the next time it runs.
///
/// Needs the demo login, passed through xcodebuild as
/// TEST_RUNNER_CWW_SCREENSHOT_EMAIL and TEST_RUNNER_CWW_SCREENSHOT_PASSWORD,
/// and skips itself without them. The server defaults to staging
/// (CWW_SCREENSHOT_BASE_URL to change it). `script/screenshots` also builds
/// that server into the app, since it builds the App Store build's
/// environment, which ignores -CWWBaseURL.
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
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", baseURL, "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"]
        app.launch()

        // 1. The welcome screen, signed out.
        let signIn = app.buttons["welcome.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        settle(2)
        keep("1-welcome", app)

        self.signIn(app)

        // 8. A new chat: the services it reaches, and the composer.
        let model = app.buttons["composer.model"]
        XCTAssertTrue(model.waitForExistence(timeout: 30), "Signing in should land on a new chat, with the app's composer")
        XCTAssertTrue(app.webViews.otherElements["Connect"].waitForExistence(timeout: 30), "The new chat should show the connected services")
        quiet(app)
        keep("8-new-chat", app)

        // 9. The model picker. A tap on the bar closes it; never one on a model, which would pick it.
        model.tap()
        let picker = app.collectionViews.staticTexts["Model"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "The model button should open the picker")
        settle(1.5)
        keep("9-models", app)
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5), "A tap outside should close the picker")
        settle(1)

        // 10. The sidebar: Decisions with its count, Bots, and the chats.
        openSidebar(app)
        XCTAssertTrue(chat(app, "Morning briefing, Mon 26 Oct").waitForExistence(timeout: 20), "The sidebar should list Ana's chats")
        settle(1.5)
        keep("10-sidebar", app)

        // 2. Bots, from the sidebar.
        app.buttons["sidebar.bots"].tap()
        let triage = app.webViews.links["GitHub issue triage"].firstMatch
        XCTAssertTrue(triage.waitForExistence(timeout: 30), "Bots should list GitHub issue triage")
        quiet(app)
        keep("2-bots", app)

        // 3. GitHub issue triage, with the issues it handled overnight.
        triage.tap()
        XCTAssertTrue(app.webViews.staticTexts["Runs"].waitForExistence(timeout: 30), "The bot's page should list its runs")
        XCTAssertTrue(text(app, "#484").waitForExistence(timeout: 10))
        quiet(app)
        keep("3-bot-runs", app)
        backToRoot(app)

        // 4. Decisions, from the sidebar: the first in focus, a question with options.
        openSidebar(app)
        app.buttons["sidebar.decisions"].tap()
        XCTAssertTrue(text(app, "Where should this week's Acme digest go?").waitForExistence(timeout: 30), "Decisions should open on the digest's question")
        quiet(app)
        keep("4-decisions", app)

        // 5. The next one: Front desk's reply to a customer, waiting for Approve or Deny.
        app.webViews.links["Next"].firstMatch.tap()
        XCTAssertTrue(text(app, "Marta Silva via Chatwoot").waitForExistence(timeout: 30), "Next should show Front desk's reply")
        XCTAssertTrue(app.webViews.buttons["Approve"].waitForExistence(timeout: 10))
        // A tapped link keeps its hover look on a touch screen until something else is tapped:
        // the count in the board's header, plain text.
        app.webViews.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "\\d+ waiting")).firstMatch.tap()
        quiet(app)
        keep("5-draft", app)
        backToRoot(app)

        // 6. A change waiting for approval: the invoice chaser's reminder to Acme, the whole card in view.
        openSidebar(app)
        chat(app, "Invoice chaser, Mon 26 Oct").tap()
        let approve = app.webViews.buttons["Approve"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 30), "The invoice chaser's email should wait for approval")
        quiet(app)
        // The kicker over the card if the whole card fits, else from the line saying what it sends;
        // the chat's "Waiting for your approval" below it kept out of sight.
        let card = app.webViews.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Send “Invoice INV/2026/0412", "region")).firstMatch
        scroll(app, showing: [(text(app, "NEEDS YOUR APPROVAL"), 24), (text(app, "Send “Invoice INV/2026/0412"), 6)], through: card, gap: 8,
               hiding: text(app, "Waiting for your approval"), dragging: text(app, "A friendly reminder"))
        keep("6-approval", app)

        // 7. The morning briefing: the run, what it searched, and its answer.
        openSidebar(app)
        chat(app, "Morning briefing, Mon 26 Oct").tap()
        XCTAssertTrue(text(app, "Good morning, Ana").waitForExistence(timeout: 30), "The briefing should show its answer")
        quiet(app)
        // From the run's question if the answer and its actions still fit, else from what it searched.
        // The actions' dots sit mid-button, so the button's foot may pass under the composer.
        let actions = app.webViews.buttons.matching(NSPredicate(format: "label == 'More actions'"))
        let searched = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Searched Slack")).firstMatch
        scroll(app, showing: [(text(app, "Do what your instructions say"), 22), (searched, 12)],
               through: actions.count > 0 ? actions.element(boundBy: actions.count - 1) : text(app, "The pricing page copy is final"), gap: -8,
               dragging: text(app, "Needs you"))
        keep("7-briefing", app)
    }

    /// Signs in on the server's page, in its sheet. A form filled while the
    /// page still settles can lose what went in (the server then shows the
    /// page again), so each field is checked, and a second try made.
    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let email = environment["CWW_SCREENSHOT_EMAIL"] ?? ""
        app.buttons["welcome.signIn"].tap()
        for _ in 0..<2 {
            let emailField = app.webViews.textFields.firstMatch
            XCTAssertTrue(emailField.waitForExistence(timeout: 30), "The sign-in page should load in a sheet")
            settle(1)
            emailField.tap()
            let typed = emailField.value as? String ?? ""
            if typed != email {
                if !typed.isEmpty { emailField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count)) }
                emailField.typeText(email)
            }
            XCTAssertEqual(emailField.value as? String, email, "The email should be in its field")
            pastePassword(into: app.webViews.secureTextFields.firstMatch, app)
            app.webViews.buttons["Sign in"].firstMatch.tap()
            if app.buttons["shell.sidebar"].waitForExistence(timeout: 40) { return }
        }
        XCTFail("Signing in should land in the shell")
    }

    /// Puts the password in without typing it: XCTest logs what it types, and
    /// a password mustn't end up in a build log. It goes by the pasteboard,
    /// emptied again straight after.
    @MainActor
    private func pastePassword(into field: XCUIElement, _ app: XCUIApplication) {
        UIPasteboard.general.string = environment["CWW_SCREENSHOT_PASSWORD"] ?? ""
        defer { UIPasteboard.general.items = [] }
        field.tap()
        settle(0.5)
        // A second tap on the focused field offers Paste; iPad's keyboard bar has it too.
        field.tap()
        let menu = app.menuItems["Paste"]
        if !menu.waitForExistence(timeout: 3) { field.press(forDuration: 1.2) }
        let paste = menu.waitForExistence(timeout: 3) ? menu : app.buttons["Paste"].firstMatch
        XCTAssertTrue(paste.exists, "The password field should offer Paste")
        paste.tap()
        settle(0.5)
        XCTAssertFalse((field.value as? String ?? "").isEmpty, "The password should be in its field")
    }

    /// Opens the sidebar from the chat at the root, its list loaded.
    @MainActor
    private func openSidebar(_ app: XCUIApplication) {
        app.buttons["shell.sidebar"].tap()
        let waiting = app.buttons["sidebar.decisions"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 20), "The sidebar should open with its list")
        let deadline = Date().addingTimeInterval(5)
        while !waiting.isHittable, Date() < deadline { settle(0.3) }
        settle(0.5)
    }

    /// A chat's row in the sidebar.
    @MainActor
    private func chat(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'sidebar.chat' AND label == %@", title)).firstMatch
    }

    /// Text on the page that contains `words`.
    @MainActor
    private func text(_ app: XCUIApplication, _ words: String) -> XCUIElement {
        app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    /// Back down to the chat at the root, where the sidebar button is.
    @MainActor
    private func backToRoot(_ app: XCUIApplication) {
        let sidebar = app.buttons["shell.sidebar"]
        for _ in 0..<4 where !sidebar.exists {
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            (back.exists ? back : app.navigationBars.buttons.element(boundBy: 0)).tap()
            settle(1.5)
        }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), "Back should lead to the chat at the root")
    }

    /// Scrolls the page so that the first of `tops` that can sits its margin
    /// under the bar while `bottom` stays `gap` points above the composer (or,
    /// if none can, as far as keeps `bottom` in view), and far enough to put
    /// `below`, what follows, wholly under the composer rather than cut by it.
    /// Each drag is slow and held at its end, so nothing flings, and starts on
    /// `handle`, plain text, so it can't press anything. A chat already in
    /// view stays at its end, where it shows no arrow back to the latest
    /// message; if something that loaded late left it short of its end and
    /// the arrow showed, the arrow takes it there (it only scrolls).
    @MainActor
    private func scroll(_ app: XCUIApplication, showing tops: [(element: XCUIElement, margin: CGFloat)], through bottom: XCUIElement, gap: CGFloat,
                        hiding below: XCUIElement? = nil, dragging handle: XCUIElement) {
        let bar = app.navigationBars.firstMatch.frame.maxY
        let composer = app.otherElements["composer"]
        let floor = composer.exists ? composer.frame.minY : app.webViews.firstMatch.frame.maxY
        let inView = {
            guard let first = tops.first else { return false }
            return first.element.frame.minY >= bar + first.margin / 2 && bottom.frame.maxY <= floor - gap
        }
        if inView() {
            let latest = app.webViews.buttons["Scroll to the latest message"]
            if latest.exists, latest.isHittable {
                latest.tap()
                settle(1.5)
            }
            if inView() {
                settle(1)
                return
            }
        }
        for _ in 0..<4 {
            // Positive moves the page down, bringing what's above into view.
            let room = floor - gap - bottom.frame.maxY
            var distance = tops.lazy.map { top, margin in bar + margin - top.frame.minY }.first { $0 <= room } ?? room
            if let below, below.exists {
                distance = min(max(distance, floor + 20 - below.frame.minY), room)
            }
            guard abs(distance) >= 20 else { break }
            let before = bottom.frame.minY
            let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)), withVelocity: .slow, thenHoldForDuration: 0.6)
            settle(1.2)
            if abs(bottom.frame.minY - before) < 2 { break }
        }
        settle(1)
    }

    /// Waits until nothing is loading, no notice shows and no keyboard is up,
    /// then a moment more for anything still moving.
    @MainActor
    private func quiet(_ app: XCUIApplication, then seconds: TimeInterval = 2) {
        let toast = app.descendants(matching: .any)["toast"]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, app.activityIndicators.count > 0 || toast.exists || app.keyboards.count > 0 {
            settle(0.5)
        }
        settle(seconds)
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func keep(_ name: String, _ app: XCUIApplication) {
        XCTAssertEqual(app.keyboards.count, 0, "\(name): no keyboard in a store screenshot")
        XCTAssertFalse(app.descendants(matching: .any)["toast"].exists, "\(name): no notice in a store screenshot")
        let screenshot = XCUIScreen.main.screenshot()
        // Also as files, where the result bundle drops attachments (seen on iPad simulators).
        if let folder = environment["CWW_SCREENSHOT_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "store-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
