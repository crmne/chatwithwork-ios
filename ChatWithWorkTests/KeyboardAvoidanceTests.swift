import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

@MainActor
@Suite("Composer overlay")
struct KeyboardAvoidanceTests {
    @Test("the page continues behind the composer while its clear margins pass touches through")
    func overlaysThePage() {
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/482139075/chats/42")!)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = screen
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = ComposerController.on(screen)
        KeyboardAvoidance.setOverlay(true, on: screen)
        window.layoutIfNeeded()
        screen.view.layoutIfNeeded()

        let page = screen.visitableView.frame
        let bar = composer.view.frame
        #expect(bar.height > 0)
        #expect(abs(page.maxY - bar.maxY) < 1, "The web view reaches behind the overlay, not just to its top")
        #expect(page.intersection(bar).height == bar.height)
        #expect(composer.view.hitTest(CGPoint(x: 2, y: bar.height / 2), with: nil) == nil)
        #expect(composer.view.hitTest(CGPoint(x: 30, y: 20), with: nil) != nil)

        KeyboardAvoidance.setOverlay(false, on: screen)
        screen.view.layoutIfNeeded()
        #expect(abs(screen.visitableView.frame.maxY - composer.view.frame.minY) < 1,
                "Older servers keep the page above the composer")
    }
}
