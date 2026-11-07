import Foundation
import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

/// The shape of every other page a screen shows until it paints, and which
/// one the path configuration picks.
@Suite("Page skeleton")
@MainActor
struct PageSkeletonTests {
    private let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
    private let insets = UIEdgeInsets(top: 116, left: 0, bottom: 34, right: 0)
    private var column: CGFloat { screen.width - 32 }
    private var floor: CGFloat { screen.height - insets.bottom }

    private func url(_ path: String) -> URL { URL(string: "https://chatwithwork.com" + path)! }

    private let configuration: PathConfiguration = {
        let url = Bundle.main.url(forResource: "path-configuration", withExtension: "json")!
        return PathConfiguration(sources: [.file(url)])
    }()

    // MARK: Which one

    @Test("is the one the bundled path configuration names", arguments: [
        ("/482139075/chats/42", PageSkeleton.Kind?.some(.chat)),
        ("/482139075/chats/42?from=7", .chat),
        ("/482139075/chats/new", .newChat),
        ("/482139075/chats/new?project_id=3", .newChat),
        ("/482139075/chats", .list),
        ("/482139075/decisions", .list),
        ("/482139075/bots", .list),
        ("/482139075/projects", .list),
        ("/482139075/settings", .settings),
        ("/482139075/settings?tab=profile", .settings),
        ("/482139075/bots/new", .form),
        ("/482139075/projects/3/edit", .form),
        ("/482139075/bots/5", .page),
        ("/482139075/bots/5?tab=setup", .page),
        ("/482139075/projects/3", .page),
        ("/482139075/chats/42/panel", .page),
        ("/482139075/settings/mcp_servers", .page),
        ("/users/sign_in", nil),
        ("/users/password/new", nil),
        ("/482139075/chats/42/files/3", nil)
    ])
    func bundled(path: String, expected: PageSkeleton.Kind?) {
        let url = url(path)
        #expect(PageSkeleton.kind(for: url, properties: configuration.properties(for: url)) == expected)
    }

    @Test("draws a plain page for a shape this build doesn't know, and nothing for none")
    func values() {
        let page = url("/482139075/bots/5")
        #expect(PageSkeleton.kind(for: page, properties: ["skeleton": "timeline"]) == .page)
        #expect(PageSkeleton.kind(for: page, properties: ["skeleton": "none"]) == nil)
        #expect(PageSkeleton.kind(for: page, properties: ["skeleton": "list"]) == .list)
        // The property wins over the route: a server can take a chat's away.
        #expect(PageSkeleton.kind(for: url("/482139075/chats/42"), properties: ["skeleton": "none"]) == nil)
    }

    // MARK: New chat

    @Test("puts the greeting at 40% of the way to the composer, and three suggestions under it")
    func newChat() {
        let layout = PageSkeletonLayout.newChat(bounds: screen, insets: insets)
        let composer = ChatSkeletonLayout(bounds: screen, insets: insets).composer
        #expect(layout.composer == composer)
        #expect(layout.boxes.isEmpty)
        #expect(layout.bones.count == 4)
        let greeting = layout.bones[0].frame
        #expect(greeting.height == 22)
        #expect(greeting.width == (column * 0.6).rounded())
        #expect(abs(greeting.midY - (insets.top + 0.4 * (composer.minY - insets.top))) <= 1)
        let pills = layout.bones.dropFirst().map(\.frame)
        #expect(pills.map(\.width) == [0.44, 0.58, 0.36].map { (column * $0).rounded() })
        #expect(pills.allSatisfy { $0.height == 32 })
        #expect(pills[0].minY == greeting.maxY + 20)
        #expect(pills[1].minY == pills[0].maxY + 8)
        #expect(layout.bones.allSatisfy { abs($0.frame.midX - screen.midX) <= 1 })
    }

    // MARK: Lists

    @Test("fills a list with rows of a mark and two lines, as far as the screen goes")
    func list() {
        let layout = PageSkeletonLayout.list(bounds: screen, insets: insets)
        #expect(layout.composer == nil)
        let rows = Int((floor - insets.top - 16) / 64)
        #expect(layout.bones.count == rows * 3)
        let circle = layout.bones[0], first = layout.bones[1], second = layout.bones[2]
        #expect(circle.shape == .circle)
        #expect(circle.frame == CGRect(x: 16, y: insets.top + 16 + 16, width: 32, height: 32))
        #expect(first.frame.minX == CGFloat(16 + 32 + 12))
        #expect(first.frame.minY == insets.top + 16 + 16)
        #expect(first.frame.height == 12)
        #expect(first.frame.width == ((column - 44) * 0.56).rounded())
        #expect(second.frame.minY == insets.top + 16 + 38)
        #expect(second.frame.height == 10)
        #expect(second.frame.width == ((column - 44) * 0.34).rounded())
        // The next row starts 64 lower, with the next widths.
        #expect(layout.bones[3].frame.minY == circle.frame.minY + 64)
        #expect(layout.bones[4].frame.width == ((column - 44) * 0.42).rounded())
        #expect(layout.bones.allSatisfy { $0.frame.maxY <= floor })
    }

    // MARK: Settings

    @Test("draws two sections of Settings, of four rows and three")
    func settings() {
        let layout = PageSkeletonLayout.settings(bounds: screen, insets: insets)
        #expect(layout.boxes.count == 2)
        let heading = layout.bones[0].frame, muted = layout.bones[1].frame
        #expect(heading == CGRect(x: 16, y: insets.top + 16, width: (column * 0.36).rounded(), height: 14))
        #expect(muted.minY == heading.maxY + 10 && muted.height == 10 && muted.width == (column * 0.72).rounded())
        let first = layout.boxes[0], second = layout.boxes[1]
        #expect(first.frame == CGRect(x: 16, y: muted.maxY + 14, width: column, height: 4 * 52))
        #expect(first.dividers == [1, 2, 3].map { first.frame.minY + CGFloat($0) * 52 })
        #expect(second.frame.height == CGFloat(3 * 52))
        #expect(second.dividers.count == 2)
        // The second section's heading, 28 under the first group.
        #expect(layout.bones.contains { $0.frame.minY == first.frame.maxY + 28 && $0.frame.height == 14 })
        // Each row: a label 16 in from the start and a short value 16 in from the end, centred.
        let inner = column - 32
        let rowBones = layout.bones.filter { $0.frame.minY > first.frame.minY && $0.frame.maxY < first.frame.maxY }
        #expect(rowBones.count == 8)
        #expect(rowBones[0].frame == CGRect(x: 32, y: first.frame.minY + 26 - 6, width: (inner * 0.44).rounded(), height: 12))
        #expect(rowBones[1].frame.maxX == first.frame.maxX - 16)
        #expect(rowBones[1].frame.width == (inner * 0.14).rounded())
        #expect(rowBones[2].frame.width == (inner * 0.56).rounded())
    }

    @Test("leaves out the rows that would pass the bottom")
    func short() {
        let small = CGRect(x: 0, y: 0, width: 402, height: 500)
        for kind in [PageSkeleton.Kind.list, .settings, .form, .page, .newChat] {
            let layout = PageSkeletonLayout(kind: kind, bounds: small, insets: insets)
            let floor = kind == .newChat ? layout.composer!.minY : small.height - insets.bottom
            #expect(layout.bones.allSatisfy { $0.frame.maxY <= floor }, "\(kind)")
            #expect(layout.boxes.allSatisfy { $0.frame.maxY <= floor }, "\(kind)")
        }
    }

    // MARK: Forms and pages

    @Test("draws a form's four fields, each a label over a box")
    func form() {
        let layout = PageSkeletonLayout.form(bounds: screen, insets: insets)
        #expect(layout.bones.map(\.frame.width) == [0.3, 0.22, 0.36, 0.26].map { (column * $0).rounded() })
        #expect(layout.bones.allSatisfy { $0.frame.height == 10 })
        #expect(layout.boxes.count == 4)
        for (label, field) in zip(layout.bones, layout.boxes) {
            #expect(field.frame == CGRect(x: 16, y: label.frame.maxY + 8, width: column, height: 44))
            #expect(field.dividers.isEmpty)
        }
        #expect(layout.bones[1].frame.minY == layout.boxes[0].frame.maxY + 20)
    }

    @Test("draws a page's heading, two lines on the text's rhythm, and a group of four rows")
    func page() {
        let layout = PageSkeletonLayout.page(bounds: screen, insets: insets)
        let heading = layout.bones[0].frame
        #expect(heading == CGRect(x: 16, y: insets.top + 16, width: (column * 0.52).rounded(), height: 20))
        let lines = Array(layout.bones[1...2]).map(\.frame)
        #expect(lines.map(\.width) == [column, (column * 0.68).rounded()])
        #expect(lines.allSatisfy { $0.height == 12 })
        #expect(abs((lines[1].minY - lines[0].minY) - 25.6) <= 1)
        #expect(layout.boxes.count == 1)
        #expect(layout.boxes[0].frame.minY == heading.maxY + 12 + 2 * 25.6 + 24)
        #expect(layout.boxes[0].frame.height == CGFloat(4 * 52))
    }

    @Test("keeps to the chat's column on a wide screen")
    func wide() {
        let wide = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let layout = PageSkeletonLayout.page(bounds: wide, insets: UIEdgeInsets(top: 74, left: 0, bottom: 20, right: 0))
        #expect(layout.boxes[0].frame.width == CGFloat(780 - 32))
        #expect(layout.boxes[0].frame.midX == CGFloat(590))
        #expect(layout.bones.allSatisfy { $0.frame.minX >= 216 && $0.frame.maxX <= 964 })
    }

    @Test("mirrors for a right-to-left language")
    func rightToLeft() {
        let layout = PageSkeletonLayout.list(bounds: screen, insets: insets)
        let mirrored = layout.mirrored(width: screen.width)
        #expect(mirrored.bones[0].frame.maxX == screen.width - 16)
        #expect(zip(layout.bones, mirrored.bones).allSatisfy { $0.frame.minX == screen.width - $1.frame.maxX && $0.frame.minY == $1.frame.minY })
    }

    // MARK: The view

    private func onScreen(_ kind: PageSkeleton.Kind) -> (PageSkeletonView, UIWindow) {
        let window = UIWindow(frame: screen)
        window.isHidden = false
        let skeleton = PageSkeletonView(kind: kind, path: "/482139075/bots")
        skeleton.frame = screen
        window.addSubview(skeleton)
        skeleton.layoutIfNeeded()
        return (skeleton, window)
    }

    @Test("sweeps, and is still under Reduce Motion, whatever the kind", arguments: PageSkeleton.Kind.allCases)
    func reduceMotion(kind: PageSkeleton.Kind) {
        let (skeleton, window) = onScreen(kind)
        defer { window.isHidden = true }
        skeleton.reducesMotion = { false }
        #expect(skeleton.isSweeping)
        skeleton.reducesMotion = { true }
        #expect(!skeleton.isSweeping)
    }

    @Test("lays out the kind it was made for")
    func viewLayout() {
        let (list, window) = onScreen(.list)
        defer { window.isHidden = true }
        #expect(list.layout == nil)
        #expect(list.pageLayout != nil)
        let (chat, other) = onScreen(.chat)
        defer { other.isHidden = true }
        #expect(chat.layout != nil)
        #expect(chat.pageLayout == nil)
    }

    @Test("reads as one element, Loading, to VoiceOver")
    func voiceOver() {
        let skeleton = PageSkeletonView(kind: .list, path: "/482139075/bots")
        #expect(skeleton.isAccessibilityElement)
        #expect(skeleton.accessibilityViewIsModal)
        #expect(skeleton.accessibilityLabel == "Loading")
    }

    // MARK: When

    private func attached(_ path: String) -> VisitableViewController {
        let url = url(path)
        let controller = HotwireWebViewController(url: url)
        controller.loadViewIfNeeded()
        PageSkeleton.attach(to: controller, url: url, properties: configuration.properties(for: url))
        return controller
    }

    @Test("is attached to a new screen of every kind the configuration names, and not to a file or sign-in", arguments: [
        ("/482139075/bots", true), ("/482139075/settings?tab=profile", true), ("/482139075/bots/new", true),
        ("/482139075/chats/new", true), ("/482139075/bots/5", true),
        ("/users/sign_in", false), ("/482139075/chats/42/files/3", false)
    ])
    func attaches(path: String, expected: Bool) {
        let controller = attached(path)
        #expect((PageSkeleton.current(on: controller) != nil) == expected)
        #expect((controller.navigationItem.titleView is TitleBone) == expected)
    }

    @Test("isn't attached twice to the same screen")
    func once() {
        let controller = attached("/482139075/bots")
        let first = PageSkeleton.current(on: controller)
        PageSkeleton.attach(to: controller, url: url("/482139075/bots"), properties: ["skeleton": "list"])
        #expect(PageSkeleton.current(on: controller) === first)
        #expect(controller.view.subviews.filter { $0 is PageSkeletonView }.count == 1)
    }

    @Test("goes once its own page has painted and the web view shows it")
    func paints() async {
        let controller = attached("/482139075/bots")
        PageSkeleton.pagePainted(path: "/482139075/chats/new", webView: nil, on: controller)
        #expect(PageSkeleton.current(on: controller) != nil)
        PageSkeleton.pagePainted(path: "/482139075/bots", webView: nil, on: controller)
        for _ in 0..<100 where PageSkeleton.current(on: controller) != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(PageSkeleton.current(on: controller) == nil)
        #expect(controller.navigationItem.titleView == nil)
    }
}
