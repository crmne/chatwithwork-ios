import HotwireNative
import UIKit
import WebKit

/// Builds every web screen and web view the navigators use.
///
/// Screens are plain `HotwireWebViewController`s, configured from outside
/// rather than subclassed: a subclass that touches the bridge delegate's
/// lifecycle is what crashed Cluster Headache Tracker's iOS app.
enum WebScreen {
    static func make(url: URL) -> VisitableViewController {
        let controller = HotwireWebViewController(url: url)
        controller.loadViewIfNeeded()

        controller.view.backgroundColor = Palette.canvas
        controller.visitableView.backgroundColor = Palette.canvas
        controller.visitableView.activityIndicatorView.color = Palette.inkMuted
        controller.visitableView.refreshControl.tintColor = Palette.inkMuted

        if case .tabRoot = AppRoute(url: url).kind {
            controller.navigationItem.largeTitleDisplayMode = .always
        } else {
            controller.navigationItem.largeTitleDisplayMode = .never
        }

        KeyboardAvoidance.install(on: controller)
        return controller
    }

    static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        TextSize.follow(webView)
        // No white flash before the first paint in dark mode.
        webView.isOpaque = false
        webView.backgroundColor = Palette.canvas
        webView.underPageBackgroundColor = Palette.canvas
        webView.scrollView.backgroundColor = Palette.canvas
        // Swiping down the conversation lowers the keyboard, as in Messages.
        webView.scrollView.keyboardDismissMode = .interactive
        // A long press on a link shouldn't open a browser preview of an app page.
        webView.allowsLinkPreview = false
        #if DEBUG
            webView.isInspectable = true
        #endif
        return webView
    }
}

/// Web pages follow the person's text size, as native text does, through
/// each web view's page zoom. Capped at 120%: the pages are laid out for the
/// default size, and larger zooms start to clip.
enum TextSize {
    private static let webViews = NSHashTable<WKWebView>.weakObjects()
    private static var observer: NSObjectProtocol?

    static func pageZoom(for category: UIContentSizeCategory) -> CGFloat {
        switch category {
        case .extraSmall: 0.85
        case .small: 0.9
        case .medium: 0.95
        case .large: 1
        case .extraLarge: 1.05
        case .extraExtraLarge: 1.1
        case .extraExtraExtraLarge: 1.15
        default: category.isAccessibilityCategory ? 1.2 : 1
        }
    }

    static func follow(_ webView: WKWebView) {
        webView.pageZoom = pageZoom(for: UIApplication.shared.preferredContentSizeCategory)
        webViews.add(webView)

        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let zoom = pageZoom(for: UIApplication.shared.preferredContentSizeCategory)
                webViews.allObjects.forEach { $0.pageZoom = zoom }
            }
        }
    }
}
