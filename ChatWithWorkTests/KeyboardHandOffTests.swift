import UIKit
import WebKit
import Testing
@testable import ChatWithWork

/// The keyboard the app holds for New chat's web composer until its page
/// takes it (`KeyboardHandOff`).
@MainActor
@Suite("The keyboard handed to New chat's web composer", .serialized)
struct KeyboardHandOffTests {
    private func window() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.makeKeyAndVisible()
        return window
    }

    /// The app's own field, out of sight, that holds the keyboard.
    private func holder(in window: UIWindow) -> UITextField? {
        window.subviews.compactMap { $0 as? UITextField }.last
    }

    @Test("words typed before a page took them are forgotten on signing out, and the keyboard is let go")
    func discardsOnSignOut() async throws {
        KeyboardHandOff.discard()
        let window = window()
        defer { window.isHidden = true }
        // A web view out of any window: no page ever takes the keyboard.
        let webView = WKWebView(frame: .zero)

        KeyboardHandOff.raise(in: window, for: webView)
        let field = try #require(holder(in: window))
        #expect(field.isFirstResponder)
        field.insertText("Person A's words")

        // Let go without a page (a slow page, the person moved on): the words wait for the next New chat.
        KeyboardHandOff.release()
        #expect(KeyboardHandOff.leftover == "Person A's words")

        KeyboardHandOff.raise(in: window, for: webView)
        let next = try #require(holder(in: window))
        next.insertText("more")
        KeyboardHandOff.discard()
        #expect(KeyboardHandOff.leftover == "")
        #expect(!next.isFirstResponder)
        #expect(next.superview == nil)

        // Nothing comes back later from the field's own watch.
        try await Task.sleep(for: .milliseconds(100))
        KeyboardHandOff.release()
        #expect(KeyboardHandOff.leftover == "")
    }

    @Test("the page a New chat leaves is never handed the keyboard, even a New chat itself, nor Turbo's preview")
    func onlyTheVisitsOwnPage() async throws {
        let window = window()
        defer { window.isHidden = true }
        let webView = WKWebView(frame: window.bounds, configuration: WKWebViewConfiguration())
        window.addSubview(webView)
        let loaded = HandOffPageLoad()
        webView.navigationDelegate = loaded
        webView.loadHTMLString(#"<!doctype html><html><body><form id="new_message"><textarea></textarea></form></body></html>"#, baseURL: URL(string: "https://chatwithwork.com/482139075/chats/new"))
        await loaded.wait()

        func focuses(leaving: String?) async throws -> Bool {
            _ = try? await webView.evaluateJavaScript("document.activeElement?.blur(); void 0")
            return try await webView.evaluateJavaScript(KeyboardHandOff.focusScript(leaving: leaving)) as? Bool == true
        }

        #expect(try await focuses(leaving: nil))
        let leaving = KeyboardHandOff.markLeaving(webView)
        #expect(try await !focuses(leaving: leaving))
        // Another New chat's mark isn't this page's.
        #expect(try await focuses(leaving: "another"))

        // The visit's own page comes with a body of its own.
        _ = try? await webView.evaluateJavaScript(#"document.body.replaceWith(Object.assign(document.createElement("body"), { innerHTML: '<form id="new_message"><textarea></textarea></form>' })); void 0"#)
        #expect(try await focuses(leaving: leaving))

        _ = try? await webView.evaluateJavaScript("document.documentElement.setAttribute('data-turbo-preview', ''); void 0")
        #expect(try await !focuses(leaving: leaving))
    }
}

/// Waits for a web view's page to load.
@MainActor
private final class HandOffPageLoad: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func wait() async {
        if finished { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { done() }

    private func done() {
        finished = true
        continuation?.resume()
        continuation = nil
    }
}
