import Testing
import UIKit
@testable import ChatWithWork

/// The screen stays on while dictation records or transcribes, and only then.
@MainActor
@Suite("Screen awake")
struct ScreenAwakeTests {
    private final class Calls {
        var values: [Bool] = []
    }

    @Test("dictation keeps the screen on from recording through transcribing, and lets go when it ends")
    func dictation() {
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/1000001/chats/1")!)
        let composer = ComposerController.on(screen)
        #expect(!composer.awake.isHolding)
        composer.view.setMode(.recording)
        #expect(composer.awake.isHolding)
        composer.view.setMode(.transcribing)
        #expect(composer.awake.isHolding)
        composer.view.setMode(.typing)
        #expect(!composer.awake.isHolding)
    }

    @Test("it turns the idle timer off while held and back on as it lets go")
    func idleTimer() {
        let calls = Calls()
        let awake = ScreenAwake(center: NotificationCenter()) { calls.values.append($0) }
        awake.isWanted = true
        awake.isWanted = true
        awake.isWanted = false
        #expect(calls.values == [true, false])
    }

    @Test("it lets go in the background and takes hold again in the foreground while still wanted")
    func background() {
        let calls = Calls()
        let center = NotificationCenter()
        let awake = ScreenAwake(center: center) { calls.values.append($0) }
        awake.isWanted = true
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        awake.isWanted = false
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        #expect(calls.values == [true, false, true, false])
    }

    @Test("it lets go when the composer leaves the screen, and when it goes")
    func goingAway() {
        let calls = Calls()
        var awake: ScreenAwake? = ScreenAwake(center: NotificationCenter()) { calls.values.append($0) }
        awake?.isWanted = true
        awake?.isOnScreen = false
        awake?.isOnScreen = true
        #expect(calls.values == [true, false, true])
        awake = nil
        #expect(calls.values == [true, false, true, false])
    }
}
