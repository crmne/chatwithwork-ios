import XCTest

/// Opt-in geometry checks against an isolated Rails test database, with synthetic fixtures.
final class LocalServerLayoutTests: XCTestCase {
    @MainActor
    func testNewChatDialogAndFirstExchange() throws {
        continueAfterFailure = false
        let base = ProcessInfo.processInfo.environment["CWW_UI_TEST_LOCAL_SERVER"]
        try XCTSkipUnless(base != nil, "Set CWW_UI_TEST_LOCAL_SERVER to an isolated Rails test server")
        let app = XCUIApplication()
        app.launchArguments = ["-CWWResetState", "YES", "-CWWBaseURL", base!, "-CWWAskForNotifications", "NO"]
        app.launch()
        app.buttons["welcome.signIn"].tap()
        let email = app.webViews.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 20))
        email.tap()
        email.typeText("user.one@example.com")
        app.webViews.secureTextFields["Password"].tap()
        app.webViews.secureTextFields["Password"].typeText("password12345")
        app.webViews.buttons["Sign in"].tap()
        let composer = app.textViews["composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        let greeting = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Alex")).firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(greeting.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        keep("new-chat")
        composer.tap()
        composer.typeText("Hello.")
        keep("new-chat-keyboard")
        let connect = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", "Connect", "Connect a service")).firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        let search = app.webViews.searchFields["Search services"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Google")
        XCTAssertFalse(composer.exists)
        keep("connect-dialog-keyboard")
        app.webViews.buttons["I'm done"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "Hello.")
        app.buttons["shell.sidebar"].tap()
        let chat = app.buttons["Native layout check"].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.tap()
        let question = app.webViews.staticTexts["Please summarize the workspace layout."]
        XCTAssertTrue(question.waitForExistence(timeout: 20))
        XCTAssertGreaterThanOrEqual(question.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        let answer = app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Your workspace connects")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        XCTAssertTrue(question.isHittable)
        XCTAssertTrue(answer.isHittable)
        keep("first-exchange")
    }

    @MainActor
    private func keep(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "local-server-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
