import HotwireNative
import UIKit
import WebKit

/// `context-menu`: a native menu anchored to an element in the page, for the
/// actions on a message (copy, retry, branch, share) behind one "more" button
/// instead of a row of small icons.
///
/// Web → native: `show` with `{items: [{title, iosImage?, androidImage?,
/// destructive?, copy?}], rect: {x, y, width, height}, scroll: {x, y},
/// title?}`, where `rect` is the anchor's `getBoundingClientRect()` and
/// `scroll` the window's `scrollX`/`scrollY`, both in CSS pixels.
/// Native → web: a reply to `show` with `{index}` when an item is chosen;
/// nothing when the menu is dismissed.
///
/// An item with `copy` text is handled here: the app copies the text and
/// says so, because a page can't write to the clipboard from a callback
/// that no tap of its own started.
final class ContextMenuComponent: BridgeComponent {
    override nonisolated class var name: String { "context-menu" }

    private weak var anchor: MenuAnchorButton?

    override func onReceive(message: Message) {
        guard message.event == "show", let data: ContextMenuData = message.data() else { return }
        present(data, for: message)
    }

    override func onViewWillDisappear() {
        anchor?.removeFromSuperview()
    }

    private func present(_ data: ContextMenuData, for message: Message) {
        guard let viewController = destinationViewController as? VisitableViewController,
              let webView = viewController.visitableView.webView
        else { return }

        anchor?.removeFromSuperview()

        let actions = data.items.enumerated().map { index, item in
            UIAction(
                title: item.title,
                image: item.iosImage.flatMap { UIImage(systemName: $0) },
                attributes: item.destructive == true ? .destructive : []
            ) { [weak self] _ in
                if let text = item.copy {
                    UIPasteboard.general.string = text
                    Haptics.play(.success)
                    ToastCenter.shared.show(String(localized: "Copied"), style: .notice)
                } else {
                    self?.reply(with: message.replacing(data: MenuSelection(index: index)))
                }
            }
        }

        let frame = data.frame(in: webView)
        let button = MenuAnchorButton(frame: webView.convert(frame, to: viewController.view))
        button.menu = UIMenu(title: data.title ?? "", children: actions)
        button.showsMenuAsPrimaryAction = true
        button.isAccessibilityElement = false
        viewController.view.addSubview(button)
        anchor = button

        Haptics.play(.selection)
        button.performPrimaryAction()
    }
}

/// An invisible button over the web element, there only to anchor the menu.
/// It leaves when the menu does.
private final class MenuAnchorButton: UIButton {
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        if let animator {
            animator.addCompletion { [weak self] in self?.removeFromSuperview() }
        } else {
            removeFromSuperview()
        }
    }
}

nonisolated struct ContextMenuData: Decodable, Equatable {
    nonisolated struct Item: Decodable, Equatable {
        let title: String
        let iosImage: String?
        let destructive: Bool?
        let copy: String?
    }

    nonisolated struct Rect: Decodable, Equatable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    nonisolated struct Point: Decodable, Equatable {
        let x: Double
        let y: Double
    }

    let items: [Item]
    let rect: Rect
    let scroll: Point?
    let title: String?

    /// The anchor in the web view's coordinates. The rect is relative to the
    /// layout viewport, in CSS pixels; adding the scroll offset gives document
    /// coordinates, which WebKit's scroll view shows at `zoom` points per CSS
    /// pixel (its zoom scale times the page zoom) and `contentOffset`.
    @MainActor
    func frame(in webView: WKWebView) -> CGRect {
        frame(zoom: webView.scrollView.zoomScale * webView.pageZoom, contentOffset: webView.scrollView.contentOffset)
    }

    func frame(zoom: CGFloat, contentOffset: CGPoint) -> CGRect {
        let scroll = scroll ?? Point(x: 0, y: 0)
        return CGRect(
            x: (rect.x + scroll.x) * zoom - contentOffset.x,
            y: (rect.y + scroll.y) * zoom - contentOffset.y,
            width: rect.width * zoom,
            height: rect.height * zoom
        )
    }
}
