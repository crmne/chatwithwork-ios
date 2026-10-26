import XCTest

/// Notifications against a Chat with Work server of your own, end to end:
/// turning them on registers the phone's token and hands the app its
/// notification key; a question's Live Activity shows its steps as the
/// server pushes them; the answer's notification shows its words, which the
/// notification service extension fetched from the server; and with
/// previews hidden in iOS's settings, only what happened shows.
///
/// Needs a development server reachable from the simulator, which really
/// answers and sends pushes (APNs credentials, and a running job worker),
/// with a login of its own: CWW_UI_TEST_BASE_URL, CWW_UI_TEST_EMAIL and
/// CWW_UI_TEST_PASSWORD (TEST_RUNNER_ prefixed through xcodebuild). Skipped
/// without them. Screenshots go to CWW_UI_TEST_SHOTS as well as the result
/// bundle. It leaves the app's previews set to Never in iOS's settings.
final class LocalServerTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(environment["CWW_UI_TEST_PASSWORD"]?.isEmpty != false, "No local server login given")
    }

    @MainActor
    func testNotificationWordsAndLiveSteps() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", environment["CWW_UI_TEST_BASE_URL"] ?? "http://localhost:3000",
                               "-CWWAskForNotifications", "NO", "-CWWToastSeconds", "2"]
        app.launch()
        signIn(app)
        turnOnNotifications(app)

        ask(app, environment["CWW_UI_TEST_QUESTION"] ?? "Run Python code that waits 25 seconds and then prints the sum of the primes below 1000, then search the help center for credits, and tell me both in two sentences.")
        XCUIDevice.shared.press(.home)
        followLiveActivity(name: "steps")

        // The answer's notification, with the words the extension fetched.
        let banner = springboard.otherElements["Notification"].firstMatch
        _ = banner.waitForExistence(timeout: 30)
        keep("answer-banner")
        openNotificationCenter()
        keep("answer-in-notification-center")
        closeNotificationCenter()

        // Previews off in iOS's settings: only what happened shows.
        hidePreviews()
        app.activate()
        ask(app, environment["CWW_UI_TEST_SECOND_QUESTION"] ?? "In one sentence, what can Chat with Work do on a phone? Check the help center.")
        XCUIDevice.shared.press(.home)
        _ = banner.waitForExistence(timeout: 45)
        settle(2)
        keep("hidden-preview-banner")
        openNotificationCenter()
        keep("hidden-preview-in-notification-center")
        closeNotificationCenter()
    }

    // MARK: Steps

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let welcome = app.buttons["welcome.signIn"]
        if !welcome.waitForExistence(timeout: 30) { keep("launch") }
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

    /// Settings › Notifications › Turn on, and iOS's prompt: the page
    /// registers the token, and hands the app its notification key.
    @MainActor
    private func turnOnNotifications(_ app: XCUIApplication) {
        app.buttons["shell.sidebar"].tap()
        let person = app.buttons["sidebar.person"]
        XCTAssertTrue(person.waitForExistence(timeout: 20), "The sidebar should load")
        person.tap()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let notifications = app.webViews.links["Notifications"].firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 15))
        notifications.tap()
        // A simulator that allowed them already shows them on.
        let turnOn = app.webViews.buttons["Turn on"].firstMatch
        if turnOn.waitForExistence(timeout: 8) {
            turnOn.tap()
            let allow = springboard.alerts.buttons["Allow"]
            if allow.waitForExistence(timeout: 10) { allow.tap() }
        }
        settle(6)
        keep("notifications-on")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let close = app.buttons["sheet.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        settle(2)
    }

    @MainActor
    private func ask(_ app: XCUIApplication, _ question: String) {
        let text = app.textViews["composer.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 20))
        text.tap()
        text.typeText(question)
        app.buttons["composer.send"].tap()
        settle(4)
        keep("asked")
    }

    /// The Dynamic Island while the answer works, and its Lock Screen
    /// presentation in Notification Center as the steps change.
    @MainActor
    private func followLiveActivity(name: String) {
        for index in 0..<6 {
            settle(1.5)
            keep("\(name)-island-\(index)")
            openNotificationCenter()
            // iOS asks whether the app may (go on) show(ing) Live Activities.
            for answer in ["Always Allow", "Allow"] where springboard.buttons[answer].firstMatch.exists {
                springboard.buttons[answer].firstMatch.tap()
                break
            }
            keep("\(name)-lock-screen-\(index)")
            closeNotificationCenter()
        }
    }

    /// iOS's Settings › Apps › the app › Notifications › Show Previews › Never.
    @MainActor
    private func hidePreviews() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let apps = settings.buttons["com.apple.settings.apps"]
        for _ in 0..<8 where !(apps.exists && apps.isHittable) {
            settings.swipeUp()
        }
        XCTAssertTrue(apps.waitForExistence(timeout: 10))
        apps.tap()
        for label in [environment["CWW_UI_TEST_APP_NAME"] ?? "CWW Dev", "Notifications", "Show Previews", "Never"] {
            let row = labelled(label, in: settings)
            if !row.waitForExistence(timeout: 5) {
                for _ in 0..<6 where !row.exists { settings.swipeUp() }
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5), label)
            row.tap()
            settle(1)
        }
        keep("show-previews-never")
        settings.terminate()
    }

    /// Settings draws its rows as buttons, cells or text, by version.
    @MainActor
    private func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND elementType IN %@", label,
            [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.staticText.rawValue])).firstMatch
    }

    @MainActor
    private func openNotificationCenter() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7)))
        settle(1.5)
    }

    @MainActor
    private func closeNotificationCenter() {
        XCUIDevice.shared.press(.home)
        settle(1)
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func keep(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        if let folder = environment["CWW_UI_TEST_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("local-\(name).png"))
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "local-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
