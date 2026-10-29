import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

@MainActor
@Suite("Composer overlay")
struct KeyboardAvoidanceTests {
    @Test("a web modal hides the overlay, releases its inset and preserves the draft")
    func hidesForModal() throws {
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/482139075/chats/42")!)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = screen
        window.isHidden = false
        defer { window.isHidden = true }
        let composer = ComposerController.on(screen)
        let showing = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"overlay":true}"#.utf8))
        let hidden = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"overlay":true,"visible":false}"#.utf8))
        composer.update(showing, connected: true)
        composer.view.textView.text = "Hello."
        window.layoutIfNeeded()
        screen.view.layoutIfNeeded()
        var layouts: [ComposerAction] = []
        composer.send = { layouts.append($0) }
        composer.update(hidden, connected: false)
        screen.view.layoutIfNeeded()
        #expect(composer.view.isHidden)
        #expect(composer.view.textView.text == "Hello.")
        #expect(layouts.contains(.layout(height: 0, width: Double(screen.visitableView.bounds.width))))
        composer.update(showing, connected: false)
        #expect(!composer.view.isHidden)
        #expect(composer.view.textView.text == "Hello.")
    }

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
