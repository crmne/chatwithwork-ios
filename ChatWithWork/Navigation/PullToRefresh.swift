import HotwireNative
import ObjectiveC
import UIKit
import WebKit

/// Pulling a page down at its top brings it up to date in place, as the
/// page does itself coming back from the background: the page's
/// `window.chatWithWork.refresh()` morphs a fresh copy of a chat's frame in,
/// keeping what's typed, the focus and the scroll, and refreshes any other
/// page by morphing it (docs/server-contract.md, "Pull to refresh"). Hotwire
/// Native's own refresh reloads the page from scratch, which ran every
/// entrance again and took the keyboard away. The control spins until the
/// page's promise settles. A server without the call gets Hotwire Native's
/// refresh.
@MainActor
final class PullToRefresh: NSObject {
    private static var key: UInt8 = 0
    private weak var controller: VisitableViewController?

    private init(controller: VisitableViewController) {
        self.controller = controller
    }

    static func install(on controller: VisitableViewController) {
        let handler = PullToRefresh(controller: controller)
        objc_setAssociatedObject(controller, &key, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let control = controller.visitableView.refreshControl
        control.removeTarget(controller.visitableView, action: nil, for: .valueChanged)
        control.addTarget(handler, action: #selector(pulled(_:)), for: .valueChanged)
    }

    private static let script = """
    if (!window.chatWithWork || !window.chatWithWork.refresh) return false
    await window.chatWithWork.refresh()
    return true
    """

    @objc private func pulled(_ control: UIRefreshControl) {
        guard let controller, let webView = controller.visitableView.webView else {
            control.endRefreshing()
            return
        }

        webView.callAsyncJavaScript(Self.script, arguments: [:], in: nil, in: .page) { [weak controller] result in
            if case let .success(value) = result, value as? Bool == true {
                control.endRefreshing()
            } else if let controller {
                // Hotwire Native's refresh ends the control itself once the page loads again.
                controller.visitableDelegate?.visitableDidRequestRefresh(controller)
            } else {
                control.endRefreshing()
            }
        }
    }
}
