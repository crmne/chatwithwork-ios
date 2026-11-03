import Testing
import UIKit
import WebKit
@testable import ChatWithWork

/// A chat runs under the system's bar, as every screen does, and the bar's
/// own scroll edge effect fades what scrolls up into it.
@MainActor
@Suite("Chat bar")
struct ChatBarTests {
    private let chat = URL(string: "https://chatwithwork.com/482139075/chats/42")!
    private let newChat = URL(string: "https://chatwithwork.com/482139075/chats/new")!

    @Test("a chat and the new chat page keep the system's bar and run under it")
    func systemBar() {
        for url in [chat, newChat] {
            let screen = WebScreen.make(url: url)
            #expect(screen.edgesForExtendedLayout.contains(.top))
            #expect(screen.navigationItem.standardAppearance == nil)
            #expect(screen.navigationItem.scrollEdgeAppearance == nil)
        }
    }

    @Test("the page's scroll view softens what scrolls under the bar")
    func softEdge() throws {
        guard #available(iOS 26.0, *) else { return }
        let webView = WebScreen.makeWebView(configuration: WKWebViewConfiguration())
        #expect(webView.scrollView.topEdgeEffect.style == .soft)
    }

    @Test("the page gets no room for a fade of its own")
    func noPageRoom() {
        let webView = WebScreen.makeWebView(configuration: WKWebViewConfiguration())
        #expect(!webView.configuration.userContentController.userScripts.contains { $0.source.contains("--native-top-bar-height") })
    }
}
