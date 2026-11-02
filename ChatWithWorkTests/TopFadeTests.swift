import Testing
import UIKit
import WebKit
@testable import ChatWithWork

/// A chat's bar has no surface and its content fades out below the title;
/// every other screen keeps its bar.
@MainActor
@Suite("Top fade")
struct TopFadeTests {
    private let chat = URL(string: "https://chatwithwork.com/482139075/chats/42")!
    private let newChat = URL(string: "https://chatwithwork.com/482139075/chats/new")!
    private let settings = URL(string: "https://chatwithwork.com/482139075/settings")!

    private func fades(on screen: UIViewController) -> [TopFadeView] {
        screen.view.subviews.compactMap { $0 as? TopFadeView }
    }

    @Test("a chat and the new chat page get the fade, with a bar of no surface, and it leaves the page's touches alone")
    func chats() throws {
        for url in [chat, newChat] {
            let screen = WebScreen.make(url: url)
            let fade = try #require(fades(on: screen).first)
            #expect(!fade.isUserInteractionEnabled)
            #expect(screen.edgesForExtendedLayout.contains(.top) == false)
            for appearance in [screen.navigationItem.standardAppearance, screen.navigationItem.scrollEdgeAppearance] {
                let bar = try #require(appearance)
                #expect(bar.backgroundColor == nil && bar.backgroundEffect == nil && bar.shadowColor == nil)
            }
        }
    }

    @Test("the fade steps aside for a web dialog, as the composer does")
    func dialog() throws {
        let screen = WebScreen.make(url: chat)
        let fade = try #require(fades(on: screen).first)
        let composer = ComposerController.on(screen)
        let hidden = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"overlay":true,"visible":false}"#.utf8))
        let showing = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"overlay":true}"#.utf8))
        composer.update(hidden, connected: true)
        #expect(fade.isHidden)
        composer.update(showing, connected: true)
        #expect(!fade.isHidden)
    }

    @Test("other pages keep their bar")
    func otherPages() {
        let screen = WebScreen.make(url: settings)
        #expect(fades(on: screen).isEmpty)
        #expect(screen.navigationItem.standardAppearance == nil)
    }

    @Test("the fade eases from solid canvas to clear")
    func ease() {
        #expect(TopFade.stops.first?.alpha == 1)
        #expect(TopFade.stops.last?.alpha == 0)
        #expect(TopFade.stops.first?.location == 0)
        #expect(TopFade.stops.last?.location == 1)
        #expect(zip(TopFade.stops, TopFade.stops.dropFirst()).allSatisfy { $0.alpha > $1.alpha && $0.location < $1.location })
    }

    @Test("the fade is in the theme's canvas, and follows the theme")
    func theme() throws {
        let fade = TopFadeView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.addSubview(fade)
        window.isHidden = false
        defer { window.isHidden = true }

        func top() throws -> UIColor {
            let colors = try #require((fade.layer as? CAGradientLayer)?.colors as? [CGColor])
            return UIColor(cgColor: try #require(colors.first))
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
            let canvas = Palette.canvas.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            #expect(try top().cgColor.components == canvas.cgColor.components)
        }
    }

    @Test("every web view tells the page how much the fade covers, as the page starts")
    func pageIsTold() {
        let configuration = WKWebViewConfiguration()
        let webView = WebScreen.makeWebView(configuration: configuration)
        let script = webView.configuration.userContentController.userScripts.first { $0.source.contains("--native-top-bar-height") }
        #expect(script?.source.contains("'24px'") == true)
        #expect(script?.injectionTime == .atDocumentStart)
    }

    @Test("a chat's buttons leave out the glass, and other screens' keep it")
    func buttons() throws {
        guard #available(iOS 26.0, *) else { return }
        let chatScreen = WebScreen.make(url: chat)
        let otherScreen = WebScreen.make(url: settings)
        let item = UIBarButtonItem(systemItem: .add)
        let otherItem = UIBarButtonItem(systemItem: .add)
        NavigationBarItems.set(item, slot: .shell, side: .trailing, on: chatScreen)
        NavigationBarItems.set(otherItem, slot: .shell, side: .trailing, on: otherScreen)
        #expect(item.hidesSharedBackground)
        #expect(!otherItem.hidesSharedBackground)
    }
}
