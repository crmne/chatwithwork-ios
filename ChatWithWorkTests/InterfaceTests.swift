import Foundation
import HotwireNative
import Testing
import UIKit
import WebKit
@testable import ChatWithWork

@Suite("Interface")
struct InterfaceTests {
    @Test("says plainly why a page didn't load")
    func errorCopy() throws {
        let offline = ErrorCopy(.web(WebError(urlError: URLError(.notConnectedToInternet))))
        #expect(offline.title == "You're offline")
        #expect(offline.symbol == "wifi.slash")

        let timeout = ErrorCopy(.web(WebError(urlError: URLError(.timedOut))))
        #expect(timeout.title == "This is taking too long")

        let unreachable = ErrorCopy(.web(WebError(urlError: URLError(.cannotFindHost))))
        #expect(unreachable.title == "Can't reach Chat with Work")

        let missing = ErrorCopy(.http(try #require(HTTPError(statusCode: 404))))
        #expect(missing.title == "This page isn't here")

        let forbidden = ErrorCopy(.http(try #require(HTTPError(statusCode: 403))))
        #expect(forbidden.title == "You don't have access")

        let broken = ErrorCopy(.http(try #require(HTTPError(statusCode: 502))))
        #expect(broken.title == "Something went wrong")
    }

    @Test("matches Live Wire's tokens in both appearances")
    func palette() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        #expect(hex(Palette.canvas.resolvedColor(with: light)) == "F3F5F9")
        #expect(hex(Palette.canvas.resolvedColor(with: dark)) == "06070B")
        #expect(hex(Palette.ink.resolvedColor(with: light)) == "0A0D14")
        #expect(hex(Palette.ink.resolvedColor(with: dark)) == "E9ECF4")
        #expect(hex(Palette.negative.resolvedColor(with: dark)) == "FF6644")
    }

    @Test("resolves its colors on any thread, as SwiftUI does when it lays out text")
    func colorsResolveOffTheMainThread() async {
        let ink = Palette.ink
        let resolved = await Task.detached {
            ink.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        }.value
        #expect(hex(resolved) == "E9ECF4")
    }

    @Test("scales pages' text with the system text size, 85% to 140%")
    func textSize() {
        #expect(TextSize.percent(for: .extraSmall) == 85)
        #expect(TextSize.percent(for: .large) == 100)
        #expect(TextSize.percent(for: .extraExtraExtraLarge) == 115)
        #expect(TextSize.percent(for: .accessibilityMedium) == 120)
        #expect(TextSize.percent(for: .accessibilityExtraExtraExtraLarge) == 140)
        #expect(TextSize.script(percent: 140).contains("'-webkit-text-size-adjust', '140%', 'important'"))
    }

    @Test("adds the size's script once, and a new one when the size changes, keeping the others")
    @MainActor
    func textSizeScripts() {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: "window.other = 1", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        TextSize.install(100, in: controller)
        TextSize.install(100, in: controller)
        #expect(controller.userScripts.count == 2)
        TextSize.install(140, in: controller)
        #expect(controller.userScripts.count == 3)
        #expect(controller.userScripts.first?.source == "window.other = 1")
        #expect(controller.userScripts.last?.source == TextSize.script(percent: 140))
    }

    @Test("a page's text, its root and rem with it, scale, the page stays the screen's width, and the zoom stays 1")
    @MainActor
    func textSizeInAPage() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.isHidden = false
        defer { window.isHidden = true }
        let webView = WKWebView(frame: window.bounds, configuration: WKWebViewConfiguration())
        window.addSubview(webView)
        TextSize.apply(140, to: webView)
        let loaded = PageLoad()
        webView.navigationDelegate = loaded
        // The page asks for 100%, as Tailwind's preflight does.
        webView.loadHTMLString(#"<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>html{-webkit-text-size-adjust:100%}</style></head><body><button id=b style="font-size:14px">OK</button><p id=p style="font-size:14px;line-height:20px">Words</p></body></html>"#, baseURL: nil)
        await loaded.wait()
        let measured = try await webView.evaluateJavaScript("[getComputedStyle(document.documentElement).fontSize, getComputedStyle(document.getElementById('b')).fontSize, getComputedStyle(document.getElementById('p')).lineHeight, document.documentElement.scrollWidth, innerWidth].join(' ')") as? String
        #expect(measured == "22.4px 19.6px 28px 393 393")
        #expect(webView.pageZoom == 1)

        // A change of size reaches the page open now.
        TextSize.apply(100, to: webView)
        try await Task.sleep(for: .milliseconds(300))
        let changed = try await webView.evaluateJavaScript("getComputedStyle(document.getElementById('b')).fontSize") as? String
        #expect(changed == "14px")
    }

    @Test("reads colors the bridge sends", arguments: [("#0A0D14", "0A0D14"), ("ff6644", "FF6644")])
    func hexColors(input: String, expected: String) throws {
        #expect(hex(try #require(UIColor(hex: input))) == expected)
    }

    @Test("ignores colors it can't read", arguments: [nil, "", "red", "#12345"] as [String?])
    func badColors(input: String?) {
        #expect(UIColor(hex: input) == nil)
    }

    private func hex(_ color: UIColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
    }
}

/// Waits for a web view's page to load.
@MainActor
private final class PageLoad: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func wait() async {
        if finished { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done() }

    private func done() {
        finished = true
        continuation?.resume()
        continuation = nil
    }
}
