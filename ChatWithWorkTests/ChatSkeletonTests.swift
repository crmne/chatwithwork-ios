import Foundation
import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

/// The shape of a chat a screen shows until its page paints.
@Suite("Chat skeleton")
@MainActor
struct ChatSkeletonTests {
    private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
    private let insets = UIEdgeInsets(top: 116, left: 0, bottom: 34, right: 0)

    private func url(_ path: String) -> URL { URL(string: "https://chatwithwork.com" + path)! }

    @Test("from a server without `skeleton`, shows for a chat and nothing else", arguments: [
        ("/482139075/chats/42", true),
        ("/chats/42", true),
        ("/482139075/chats/42?from=7", true),
        ("/482139075/chats/new", false),
        ("/482139075/chats", false),
        ("/482139075/chats/42/files/3", false),
        ("/482139075/bots", false),
        ("/482139075/decisions", false),
        ("/users/sign_in", false)
    ])
    func covers(path: String, expected: Bool) {
        #expect(PageSkeleton.kind(for: url(path), properties: [:]) == (expected ? .chat : nil))
    }

    @Test("lays out two questions and two answers, top down under the bar")
    func layout() {
        let layout = ChatSkeletonLayout(bounds: screen, insets: insets)
        #expect(layout.bones.map(\.kind) == [.question, .line, .line, .line, .line, .question, .line, .line, .line])
        #expect(layout.bones[0].frame.minY == insets.top + ChatSkeletonLayout.topGap)
        for (above, below) in zip(layout.bones, layout.bones.dropFirst()) {
            #expect(above.frame.maxY <= below.frame.minY)
        }
    }

    @Test("sizes questions as the spec says, against the right margin")
    func questions() {
        let layout = ChatSkeletonLayout(bounds: screen, insets: insets)
        let column = screen.width - 32
        let questions = layout.bones.filter { $0.kind == .question }.map(\.frame)
        #expect(questions[0].width == (column * 0.62).rounded())
        #expect(questions[0].height == 44)
        #expect(questions[1].width == (column * 0.45).rounded())
        #expect(questions[1].height == 36)
        #expect(questions.allSatisfy { $0.maxX == screen.width - 16 })
    }

    @Test("sets answers on the page's rhythm, with a short last line")
    func answers() {
        let layout = ChatSkeletonLayout(bounds: screen, insets: insets)
        let column = screen.width - 32
        let lines = Array(layout.bones.filter { $0.kind == .line }.map(\.frame).prefix(4))
        #expect(lines.allSatisfy { $0.height == 12 && $0.minX == 16 })
        #expect(lines[0].width == column)
        #expect(lines[3].width == (column * 0.6).rounded())
        #expect(abs((lines[1].minY - lines[0].minY) - 25.6) <= 1)
    }

    @Test("keeps to the composer's column on a wide screen")
    func wide() {
        let layout = ChatSkeletonLayout(bounds: CGRect(x: 0, y: 0, width: 1180, height: 820), insets: UIEdgeInsets(top: 74, left: 0, bottom: 20, right: 0))
        #expect(layout.composer.width == CGFloat(780 - 32))
        #expect(layout.composer.midX == 590)
        #expect(layout.bones.allSatisfy { $0.frame.minX >= layout.composer.minX && $0.frame.maxX <= layout.composer.maxX })
    }

    @Test("puts the composer's placeholder exactly where the native composer's box rests")
    func composerMatches() throws {
        let window = UIWindow(frame: screen)
        let holder = UIViewController()
        window.rootViewController = holder
        window.isHidden = false
        let composer = ComposerView()
        composer.translatesAutoresizingMaskIntoConstraints = false
        holder.view.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: holder.view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: holder.view.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: holder.view.bottomAnchor)
        ])
        holder.view.layoutIfNeeded()
        let box = try #require(rainbowBox(in: composer))
        #expect(box.bounds.height == ComposerView.restingBoxHeight)
        #expect(composer.bounds.maxY - box.convert(box.bounds, to: composer).maxY == ComposerView.restingBottomGap)
        #expect(box.convert(box.bounds, to: composer).minX == ChatSkeletonLayout.margin)
    }

    private func rainbowBox(in view: UIView) -> RainbowBox? {
        if let box = view as? RainbowBox { return box }
        return view.subviews.lazy.compactMap(rainbowBox(in:)).first
    }

    // MARK: The sweep

    private func skeletonOnScreen() -> (PageSkeletonView, UIWindow) {
        let window = UIWindow(frame: screen)
        window.isHidden = false
        let skeleton = PageSkeletonView(kind: .chat, path: "/482139075/chats/42")
        skeleton.frame = screen
        window.addSubview(skeleton)
        skeleton.layoutIfNeeded()
        return (skeleton, window)
    }

    @Test("sweeps while motion is welcome, is still under Reduce Motion, and follows the setting")
    func reduceMotion() {
        let (skeleton, window) = skeletonOnScreen()
        defer { window.isHidden = true }
        skeleton.reducesMotion = { false }
        #expect(skeleton.isSweeping)

        skeleton.reducesMotion = { true }
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        #expect(!skeleton.isSweeping)

        skeleton.reducesMotion = { false }
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        #expect(skeleton.isSweeping)
    }

    @Test("reads as one element to VoiceOver")
    func voiceOver() {
        let skeleton = PageSkeletonView(kind: .chat, path: "/chats/1")
        #expect(skeleton.isAccessibilityElement)
        #expect(skeleton.accessibilityLabel == "Loading chat")
    }

    // MARK: Going away

    private func attached(_ path: String = "/482139075/chats/42") -> VisitableViewController {
        let controller = HotwireWebViewController(url: url(path))
        controller.loadViewIfNeeded()
        PageSkeleton.attach(to: controller, url: url(path), properties: [:])
        return controller
    }

    @Test("isn't attached to a new chat by a server without `skeleton`")
    func notOnNewChat() {
        #expect(PageSkeleton.current(on: attached("/482139075/chats/new")) == nil)
    }

    @Test("draws a title bone while the screen has no title, and gives the bar back as it goes")
    func titleBone() {
        let controller = attached()
        #expect(controller.navigationItem.titleView is TitleBone)
        PageSkeleton.dismiss(on: controller, animated: false)
        #expect(controller.navigationItem.titleView == nil)
        #expect(PageSkeleton.current(on: controller) == nil)
    }

    @Test("stays for a page from before, and goes for its own page")
    func paints() async {
        let controller = attached()
        PageSkeleton.pagePainted(path: "/482139075/chats/new", webView: nil, on: controller)
        #expect(PageSkeleton.current(on: controller) != nil)

        PageSkeleton.pagePainted(path: "/482139075/chats/42", webView: nil, on: controller)
        await settled(controller)
        #expect(PageSkeleton.current(on: controller) == nil)
    }

    private func settled(_ controller: UIViewController) async {
        for _ in 0..<100 where PageSkeleton.current(on: controller) != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("waits for the web view to show and the chat to find its place", arguments: [
        (true, 3000.0, 700.0, 2300.0, false),   // Hotwire still hides the page
        (false, 3000.0, 700.0, -116.0, false),  // shown, but still at the top of a long chat
        (false, 3000.0, 700.0, 2300.0, true),   // at its place
        (false, 500.0, 700.0, -116.0, true)     // a short chat stays where it is
    ])
    func settling(hidden: Bool, content: Double, visible: Double, offset: Double, expected: Bool) {
        #expect(PageSkeleton.isSettled(webViewHidden: hidden, contentHeight: content, visibleHeight: visible, offset: offset, restingOffset: -116) == expected)
    }

    @Test("never stays past its timeout")
    func timeout() async {
        let before = PageSkeleton.timeout
        PageSkeleton.timeout = .milliseconds(20)
        defer { PageSkeleton.timeout = before }
        let controller = attached()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(PageSkeleton.current(on: controller) == nil)
    }
}
