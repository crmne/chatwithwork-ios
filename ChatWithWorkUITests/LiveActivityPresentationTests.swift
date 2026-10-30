import XCTest

/// System-rendered Live Activities with synthetic data and no push credentials.
final class LiveActivityPresentationTests: XCTestCase {
    @MainActor
    func testSystemPresentations() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let scenarios = ProcessInfo.processInfo.environment["CWW_ACTIVITY_SCENARIOS"]?.split(separator: ",").map(String.init)
            ?? ["search", "run", "approval_waiting", "input_requested", "answered", "failed", "stopped", "long"]
        for scenario in scenarios {
            app.launchArguments = ["-CWWLiveActivityPreview", scenario, "-CWWAskForNotifications", "NO"]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            // ActivityKit requests the system surface asynchronously after activation.
            Thread.sleep(forTimeInterval: 2)
            XCUIDevice.shared.press(.home)
            let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
            top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7)))
            let headline = switch scenario {
            case "search": "Searching your work tools"
            case "run": "Running an agent"
            case "legacy": "Writing the answer"
            case "long": "Reading information in your connected work tools"
            case "approval_waiting": "Approval needed"
            case "input_requested": "Your input needed"
            case "answered": "Answer ready"
            case "failed": "Couldn't finish"
            case "stopped": "Stopped"
            default: "Open chat for an update"
            }
            // A cold widget-extension launch after a device appearance change
            // can take longer than the app itself. Wait for the actual surface.
            XCTAssertTrue(springboard.staticTexts[headline].waitForExistence(timeout: 30), headline)
            if !["search", "run", "long", "legacy"].contains(scenario) { XCTAssertFalse(springboard.staticTexts["Elapsed time"].exists) }
            // First-use permission controls arrive with the Activity surface,
            // not necessarily before its headline. Keep them out of evidence.
            for answer in ["Always Allow", "Allow"] {
                let button = springboard.buttons[answer].firstMatch
                if button.waitForExistence(timeout: 2) {
                    button.tap()
                    expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: button)
                    waitForExpectations(timeout: 10)
                }
            }
            keep("lock-\(scenario)")
            XCUIDevice.shared.press(.home)
            if ["search", "run", "long", "legacy"].contains(scenario) {
                XCTAssertTrue(springboard.icons["CWW Dev"].waitForExistence(timeout: 10))
                keep("island-compact-\(scenario)")
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 1.2)
                XCTAssertTrue(springboard.staticTexts[headline].waitForExistence(timeout: 10))
                let visible = NSPredicate(format: "exists == true AND hittable == true")
                expectation(for: visible, evaluatedWith: springboard.staticTexts[headline])
                waitForExpectations(timeout: 10)
                keep("island-expanded-\(scenario)")
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
