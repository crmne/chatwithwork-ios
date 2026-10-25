import HotwireNative
import ObjectiveC
import UIKit

/// The navigation controller for every stack. When it is presented as a
/// sheet, its first screen gets a close button on the leading side; on every
/// stack it keeps pages pinned to their top edge (TopEdge).
final class AppNavigationController: HotwireNavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Lists (Bots, Projects, Settings) show large titles; every other screen opts out (WebScreen).
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
        // A chat replacing the root (the path configuration's replace_root)
        // fades in, rather than sliding in as if pushed.
        let replacesRoot = animated && viewControllers.count == 1 && !self.viewControllers.isEmpty && self.viewControllers.first !== viewControllers.first
        if replacesRoot {
            let fade = CATransition()
            fade.duration = 0.2
            fade.type = .fade
            view.layer.add(fade, forKey: kCATransition)
        }
        super.setViewControllers(viewControllers, animated: animated && !replacesRoot)
        installCloseButtonWhenPresented()
        decorate()
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)
        decorate()
    }

    /// The sidebar shell's buttons on the main stack's screens.
    private func decorate() {
        guard let shell = parent as? SidebarShell ?? parent?.parent as? SidebarShell else { return }
        for (index, controller) in viewControllers.enumerated() {
            shell.decorate(controller, isRoot: index == 0)
        }
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
///
/// It also keeps it there through WebKit's zoom reset (`follow`). A new
/// document first lays out at WebKit's 980-point default viewport, zoomed out
/// to fit, then takes its own `width=device-width, initial-scale=1` and zooms
/// back to 1. UIScrollView keeps the visible centre while zooming, which
/// moves the offset hundreds of points down the page; the navigation
/// controller reads that as a scroll and collapses the large title before
/// the page is shown. WebKit then puts the page back at its top, but under
/// the collapsed bar, so every screen arrived with a small title.
enum TopEdge {
    private nonisolated(unsafe) static var key: UInt8 = 0
    private nonisolated(unsafe) static var zoomKey: UInt8 = 0

    /// Puts a page that sat at its top edge back there after WebKit changes
    /// its zoom scale, at the inset it had before, so a large title the zoom
    /// collapsed opens again. Pinches are the person's own and left alone.
    @discardableResult
    static func follow(_ scrollView: UIScrollView) -> ZoomState {
        let state = ZoomState(scrollView)
        // Weakly: the scroll view owns the state, the state the observation.
        state.observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak state] scrollView, _ in
            MainActor.assumeIsolated {
                guard let state, let restore = state.offsetToRestore(after: scrollView) else { return }
                let zoomScale = scrollView.zoomScale
                // After WebKit finishes the transaction that zoomed, which
                // sets the offset again itself. Not if the page zoomed again
                // or someone took hold of it meanwhile.
                DispatchQueue.main.async { [weak scrollView] in
                    guard let scrollView, scrollView.zoomScale == zoomScale,
                          !scrollView.isTracking, !scrollView.isDecelerating, !scrollView.isZooming
                    else { return }
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: restore), animated: false)
                }
            }
        }
        objc_setAssociatedObject(scrollView, &zoomKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    /// What a scroll view looked like the last time it settled, so a zoom
    /// can be compared with the moment before it.
    final class ZoomState {
        var observation: NSKeyValueObservation?
        private var zoomScale: CGFloat
        private var top: CGFloat
        private var wasAtTop: Bool

        init(_ scrollView: UIScrollView) {
            zoomScale = scrollView.zoomScale
            top = -scrollView.adjustedContentInset.top
            wasAtTop = scrollView.contentOffset.y <= top + 0.5
        }

        /// The offset to put back after this change, if it was a zoom
        /// WebKit made while the page sat at its top edge.
        func offsetToRestore(after scrollView: UIScrollView) -> CGFloat? {
            if abs(scrollView.zoomScale - zoomScale) > 0.001 {
                zoomScale = scrollView.zoomScale
                let byPerson = scrollView.isZooming || scrollView.isTracking
                return wasAtTop && !byPerson ? top : nil
            }
            top = -scrollView.adjustedContentInset.top
            wasAtTop = scrollView.contentOffset.y <= top + 0.5
            return nil
        }
    }

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
