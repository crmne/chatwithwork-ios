import XCTest

/// System-rendered Live Activities with synthetic data and no push credentials.
final class LiveActivityPresentationTests: XCTestCase {
    /// Every state of Open Road on the Lock Screen and in the Island. Set
    /// `TEST_RUNNER_CWW_ACTIVITY_SCENARIOS` to a subset, and
    /// `TEST_RUNNER_CWW_ACTIVITY_LOCK_ONLY` to skip the Island.
    @MainActor
    func testSystemPresentations() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let environment = ProcessInfo.processInfo.environment
        let scenarios = environment["CWW_ACTIVITY_SCENARIOS"]?.split(separator: ",").map(String.init)
            ?? ["starting", "working", "paced", "deep", "agents", "writing", "decision", "input", "finished", "failed", "stopped", "quiet", "legacy"]
        let lockOnly = environment["CWW_ACTIVITY_LOCK_ONLY"] != nil
        for scenario in scenarios {
            app.launchArguments = ["-CWWLiveActivityPreview", scenario, "-CWWAskForNotifications", "NO"]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            // ActivityKit requests the system surface asynchronously after activation.
            Thread.sleep(forTimeInterval: 2)
            XCUIDevice.shared.press(.home)
            let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
            top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7)))
            // The card is one VoiceOver element, whatever it draws.
            let card = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Northwind' OR label CONTAINS 'waiting' OR label CONTAINS 'Answer ready' OR label CONTAINS 'finish' OR label CONTAINS 'Stopped' OR label CONTAINS 'update' OR label CONTAINS 'agents' OR label CONTAINS 'Running'")).firstMatch
            let found = card.waitForExistence(timeout: 30)
            if !found { keep("missing-\(scenario)") }
            XCTAssertTrue(found, scenario)
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
            if !lockOnly {
                Thread.sleep(forTimeInterval: 1.5)
                keep("compact-\(scenario)")
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 1.2)
                Thread.sleep(forTimeInterval: 1)
                keep("expanded-\(scenario)")
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
