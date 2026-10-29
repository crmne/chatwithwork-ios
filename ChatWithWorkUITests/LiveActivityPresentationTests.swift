import XCTest

/// System-rendered Live Activities with synthetic data and no push credentials.
final class LiveActivityPresentationTests: XCTestCase {
    @MainActor
    func testSystemPresentations() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for scenario in ["search", "approval_waiting", "answered", "failed"] {
            app.launchArguments = ["-CWWLiveActivityPreview", scenario, "-CWWAskForNotifications", "NO"]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            // ActivityKit requests the system surface asynchronously after activation.
            Thread.sleep(forTimeInterval: 2)
            XCUIDevice.shared.press(.home)
            let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
            top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7)))
            for answer in ["Always Allow", "Allow"] where springboard.buttons[answer].firstMatch.exists {
                springboard.buttons[answer].firstMatch.tap()
            }
            let headline = switch scenario {
            case "search": "Searching your work tools"
            case "approval_waiting": "Approval needed"
            case "answered": "Answer ready"
            case "failed": "Couldn't finish"
            default: "Open chat for an update"
            }
            XCTAssertTrue(springboard.staticTexts[headline].waitForExistence(timeout: 10), headline)
            if scenario != "search" { XCTAssertFalse(springboard.staticTexts["Elapsed time"].exists) }
            if scenario == "search", springboard.buttons["Allow"].firstMatch.waitForExistence(timeout: 3) {
                springboard.buttons["Allow"].firstMatch.tap()
            }
            keep("lock-\(scenario)")
            XCUIDevice.shared.press(.home)
            if scenario == "search" {
                keep("island-compact")
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 1.2)
                XCTAssertTrue(springboard.staticTexts[headline].waitForExistence(timeout: 10))
                keep("island-expanded")
                XCUIDevice.shared.press(.home)
            }
            app.terminate()
        }
    }

    @MainActor
    private func keep(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        if let folder = ProcessInfo.processInfo.environment["CWW_UI_TEST_SHOTS"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("activity-\(name).png"))
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "activity-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
