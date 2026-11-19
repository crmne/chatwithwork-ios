import HotwireNative
import SwiftUI
import Testing
import UIKit
@testable import ChatWithWork

/// The native pieces at the largest text sizes (Settings > Accessibility >
/// Larger Text, up to AX5): text grows, rows grow with it, and nothing is cut
/// to a letter or covers something else. At the default size they stay as
/// they were.
@MainActor
@Suite("Large text")
struct LargeTextTests {
    private static let state = #"{"placeholder":"Reply to Chat with Work","acceptsFiles":true,"dictation":{"url":"/d"},"webSearch":{"on":false,"disabled":false},"models":[{"name":"Claude Sonnet 5","rate":"About 6 credits per answer","selected":true,"iconName":"anthropic"},{"name":"GPT-6 Luna","selected":false,"iconName":"openai"}],"permissionModes":{"selected":"everything","options":[{"value":"ask","label":"Ask first","selected":false,"disabled":false},{"value":"everything","label":"Allow everything","selected":true,"disabled":false}]}}"#

    /// A composer across a phone's width at that text size, laid out.
    private func composer(_ category: UIContentSizeCategory, width: CGFloat = 393) throws -> (UIWindow, ComposerView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 852))
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        host.traitOverrides.preferredContentSizeCategory = category
        let view = ComposerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        view.update(try JSONDecoder().decode(ComposerState.self, from: Data(Self.state.utf8)))
        host.view.layoutIfNeeded()
        view.layoutIfNeeded()
        return (window, view)
    }

    private func frame(_ view: UIView, in composer: ComposerView) -> CGRect {
        view.convert(view.bounds, to: composer)
    }

    @Test("at the default size the model stays in the bar, beside Send", arguments: [UIContentSizeCategory.large, .extraExtraExtraLarge])
    func modelInTheBar(category: UIContentSizeCategory) throws {
        let (window, view) = try composer(category)
        defer { window.isHidden = true }
        let model = try #require(view.descendant("composer.model"))
        let send = try #require(view.descendant("composer.send"))
        #expect(view.descendant("composer.modelRow")?.isHidden == true)
        #expect(abs(frame(model, in: view).midY - frame(send, in: view).midY) < 1, "The model shares the bar with Send")
    }

    @Test("at the accessibility sizes the model takes a row of its own, its name whole", arguments: [
        UIContentSizeCategory.accessibilityMedium, .accessibilityExtraExtraExtraLarge
    ])
    func modelOnItsOwnRow(category: UIContentSizeCategory) throws {
        let (window, view) = try composer(category)
        defer { window.isHidden = true }
        let button = try #require(view.descendant("composer.model") as? UIButton)
        let row = try #require(view.descendant("composer.modelRow"))
        let send = try #require(view.descendant("composer.send"))
        let pill = try #require(view.descendant("composer.mode"))
        #expect(!row.isHidden && !button.isHidden)
        #expect(button.configuration?.title == "Claude Sonnet 5", "Its name, never only the logo")

        let model = frame(button, in: view)
        #expect(model.maxY <= frame(send, in: view).minY + 0.5, "Above the bar, not over it")
        #expect(model.maxY <= frame(pill, in: view).minY + 0.5)
        #expect(model.height >= ComposerControl.target)
        #expect(model.maxX <= view.bounds.width - 16 - 6 + 0.5, "Inside the box")

        // Every word shows: as wide as it needs, or as tall as its wrapped lines.
        let title = try #require(button.titleLabel)
        let needed = title.sizeThatFits(CGSize(width: title.bounds.width, height: .greatestFiniteMagnitude))
        #expect(title.bounds.width > 60, "More than a letter or two (\(title.bounds.width) pt)")
        #expect(title.bounds.height >= needed.height - 1, "The name isn't cut (\(title.bounds.height) of \(needed.height) pt)")
    }

    @Test("at AX5 the bar's controls keep their 44-point targets, side by side inside the box, the pill and Send included")
    func barAtTheLargestSize() throws {
        for width in [320.0, 393.0, 440.0] {
            let (window, view) = try composer(.accessibilityExtraExtraExtraLarge, width: width)
            defer { window.isHidden = true }
            let ids = ["composer.plus", "composer.dictate", "composer.webSearch", "composer.mode", "composer.send"]
            let shown = ids.compactMap { view.descendant($0) }.filter { !$0.isHidden && $0.alpha > 0 }
            #expect(shown.contains { $0.accessibilityIdentifier == "composer.send" })
            #expect(shown.contains { $0.accessibilityIdentifier == "composer.mode" })
            let frames = shown.map { frame($0, in: view) }.sorted { $0.minX < $1.minX }
            for (control, rect) in zip(shown, frames) {
                #expect(rect.height >= ComposerControl.target - 0.5, "\(control.accessibilityIdentifier ?? "") at \(width)")
                #expect(rect.minX >= 16 + 6 - 0.5 && rect.maxX <= width - 16 - 6 + 0.5, "\(control.accessibilityIdentifier ?? "") leaves the bar at \(width): \(rect)")
            }
            for (left, right) in zip(frames, frames.dropFirst()) {
                #expect(left.maxX <= right.minX + 0.5, "Controls overlap at \(width): \(left) and \(right)")
            }
        }
    }

    @Test("the placeholder wraps rather than cut, and the field opens under it")
    func placeholderWraps() throws {
        let (window, view) = try composer(.accessibilityExtraExtraExtraLarge)
        defer { window.isHidden = true }
        let placeholder = try #require(view.textView.subviews.compactMap { $0 as? UILabel }.first { $0.text == "Reply to Chat with Work" })
        let needed = placeholder.sizeThatFits(CGSize(width: placeholder.bounds.width, height: .greatestFiniteMagnitude))
        #expect(placeholder.bounds.height >= needed.height - 1, "The placeholder isn't cut")
        #expect(view.textView.bounds.height >= placeholder.frame.maxY - 1, "The field is as tall as its placeholder")
        #expect(view.textView.bounds.height <= max(placeholder.frame.maxY + 6, 40) + 1, "No empty line under it (field \(view.textView.bounds.height), placeholder ends at \(placeholder.frame.maxY), width \(placeholder.bounds.width) in \(view.textView.bounds.width))")
    }

    @Test("a file's chip sends every touch on its trailing end to its remove button, top to bottom", arguments: [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge])
    func removeTarget(category: UIContentSizeCategory) throws {
        let (window, view) = try composer(category)
        defer { window.isHidden = true }
        view.update(try JSONDecoder().decode(ComposerState.self, from: Data(#"{"placeholder":"","attachments":[{"id":"7","name":"plan.pdf","size":"1.2 MB","uploading":false}]}"#.utf8)))
        view.layoutIfNeeded()
        let remove = try #require(view.allSubviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "Remove plan.pdf" })
        let chip = try #require(remove.superview?.superview)
        let cross = remove.convert(remove.bounds, to: chip)
        for point in [CGPoint(x: chip.bounds.maxX - 1, y: 1), CGPoint(x: chip.bounds.maxX - 1, y: chip.bounds.maxY - 1), CGPoint(x: cross.minX - 8, y: chip.bounds.midY)] {
            // Through the window, as a touch arrives.
            let hit = window.hitTest(chip.convert(point, to: window), with: nil)
            #expect(hit === remove, "A touch at \(point) in a \(chip.bounds.size) chip lands on \(String(describing: hit))")
        }
        #expect(cross.width + 10 + (chip.bounds.maxX - cross.maxX) >= 34)
    }

    @Test("the words grow to 140 points at the usual sizes before scrolling, more at the largest")
    func tallestText() {
        #expect(ComposerView.tallestText(for: .large) == 140)
        #expect(ComposerView.tallestText(for: .small) == 140)
        #expect(ComposerView.tallestText(for: .accessibilityExtraExtraExtraLarge) == 220)
    }

    @Test("the bar's buttons offer the large content viewer, with their names")
    func largeContentViewer() throws {
        let (window, view) = try composer(.accessibilityExtraExtraExtraLarge)
        defer { window.isHidden = true }
        let plus = try #require(view.descendant("composer.plus"))
        #expect(plus.showsLargeContentViewer)
        #expect(plus.largeContentTitle == "Add")
        #expect(plus.largeContentImage != nil)
        #expect(plus.interactions.contains { $0 is UILargeContentViewerInteraction })
        let pill = try #require(view.descendant("composer.mode"))
        #expect(pill.showsLargeContentViewer)
        #expect(pill.largeContentTitle == "Everything")
    }

    @Test("at AX5 the pill's symbol stays on its plate and its word shows whole")
    func pillAtTheLargestSize() throws {
        let (window, view) = try composer(.accessibilityExtraExtraExtraLarge)
        defer { window.isHidden = true }
        let pill = try #require(view.descendant("composer.mode"))
        let symbol = try #require(pill.allSubviews.compactMap { $0 as? UIImageView }.first { !$0.isHidden && $0.image != nil })
        #expect(symbol.bounds.height <= ComposerModePill.plateHeight - 8, "The symbol fits on the 34-point plate (\(symbol.bounds.height) pt)")
        let label = try #require(pill.allSubviews.compactMap { $0 as? UILabel }.first)
        #expect(label.bounds.width >= label.intrinsicContentSize.width - 0.5, "\"Everything\" isn't cut (\(label.bounds.width) of \(label.intrinsicContentSize.width) pt)")
    }

    @Test("the sidebar widens at the accessibility sizes, and names take up to three lines")
    func sidebar() {
        #expect(abs(SidebarShell.sidebarWidth(in: 393, category: .large) - 393 * 0.84) < 0.01)
        #expect(SidebarShell.sidebarWidth(in: 440, category: .large) == 340)
        #expect(SidebarShell.sidebarWidth(in: 393, category: .accessibilityExtraExtraExtraLarge) > 360)
        #expect(SidebarShell.sidebarWidth(in: 1024, category: .accessibilityMedium) == 420)
        #expect(SidebarView.nameLines(.large) == 1)
        #expect(SidebarView.nameLines(.xxxLarge) == 1)
        #expect(SidebarView.nameLines(.accessibility1) == 3)
        #expect(SidebarView.nameLines(.accessibility5) == 3)
    }

    @Test("the error screen scrolls once its words don't fit, and only then", arguments: [
        (UIContentSizeCategory.large, false), (.accessibilityExtraExtraExtraLarge, true)
    ])
    func errorScreenScrolls(category: UIContentSizeCategory, scrolls: Bool) throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let host = UIHostingController(rootView: NativeErrorView(error: .web(WebError(urlError: URLError(.notConnectedToInternet))), handler: {}))
        window.rootViewController = host
        host.traitOverrides.preferredContentSizeCategory = category
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let scroll = try #require(host.view.allSubviews.compactMap { $0 as? UIScrollView }.first)
        scroll.layoutIfNeeded()
        let overflows = scroll.contentSize.height > scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom + 1
        #expect(overflows == scrolls, "content \(scroll.contentSize.height) in \(scroll.bounds.height)")
    }
}

private extension UIView {
    var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}
