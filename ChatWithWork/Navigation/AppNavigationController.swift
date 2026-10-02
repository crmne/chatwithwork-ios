import HotwireNative
import ObjectiveC
import UIKit

/// The navigation controller for every stack. When it is presented as a
/// sheet, its first screen gets a close button on the leading side; on every
/// stack it keeps pages pinned to their top edge (TopEdge).
final class AppNavigationController: HotwireNavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Tab roots show large titles; every other screen opts out (WebScreen).
        navigationBar.prefersLargeTitles = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installCloseButtonWhenPresented()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let scrollView = (topViewController as? VisitableViewController)?.visitableView.webView?.scrollView else { return }
        // The scroll view's insets settle in its own layout, just after this one.
        DispatchQueue.main.async {
            TopEdge.keepPinned(scrollView)
        }
    }

    override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        super.setViewControllers(viewControllers, animated: animated)
        installCloseButtonWhenPresented()
    }

    private func installCloseButtonWhenPresented() {
        guard presentingViewController != nil, let root = viewControllers.first else { return }
        NavigationBarItems.setCloseButton(on: root) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}

/// Keeps a page that sat at its top edge there when the bars above it change
/// height: a search bar arriving after the page loaded, or the page loading
/// before its screen was on display. A scroll view keeps its offset when its
/// insets grow, which would leave the page's top under the bars and the large
/// title collapsed.
enum TopEdge {
    private nonisolated(unsafe) static var key: UInt8 = 0

    static func keepPinned(_ scrollView: UIScrollView) {
        let top = -scrollView.adjustedContentInset.top
        let offset = scrollView.contentOffset.y
        let previous = objc_getAssociatedObject(scrollView, &key) as? CGFloat
        objc_setAssociatedObject(scrollView, &key, top, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let wasAtTop: Bool
        if let previous {
            guard abs(previous - top) >= 0.5 else { return }
            wasAtTop = abs(offset - previous) < 0.5
        } else {
            // First sight of this page: nobody has scrolled it yet.
            wasAtTop = offset <= 0
        }

        if wasAtTop, offset > top {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: top), animated: false)
        }
    }
}
