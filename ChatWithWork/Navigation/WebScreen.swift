import HotwireNative
import ObjectiveC
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
        LogoDrawView.replaceSpinner(in: controller.visitableView.activityIndicatorView, side: 72)
        controller.visitableView.refreshControl.tintColor = Palette.inkMuted

        if case .list = AppRoute(url: url).kind {
            controller.navigationItem.largeTitleDisplayMode = .always
        } else {
            controller.navigationItem.largeTitleDisplayMode = .never
        }

        KeyboardAvoidance.install(on: controller)
        PageSkeleton.attach(to: controller, url: url)
        return controller
    }

    static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []
        // The pages' service worker, which keeps opened chats readable
        // offline, runs only in a web view kept to the app-bound domains.
        configuration.limitsNavigationsToAppBoundDomains = AppBoundDomains.covers(AppEnvironment.current.baseURL)

        PagePaint.install(in: configuration)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        TextSize.follow(webView)
        PageTitle.follow(webView)
        PinchZoom.resetOnNewPage(webView)
        // No white flash before the first paint in dark mode.
        webView.isOpaque = false
        webView.backgroundColor = Palette.canvas
        webView.underPageBackgroundColor = Palette.canvas
        webView.scrollView.backgroundColor = Palette.canvas
        // Swiping down the conversation lowers the keyboard, as in Messages.
        webView.scrollView.keyboardDismissMode = .interactive
        // Every page runs under the system's bar, whose own scroll edge effect
        // softens what scrolls up into it, starting right under the title.
        // WebKit insets the page below the bar, so its top still starts clear.
        if #available(iOS 26.0, *) {
            webView.scrollView.topEdgeEffect.style = .soft
        }
        // A new page's zoom reset mustn't collapse the large title.
        TopEdge.follow(webView.scrollView)
        // A long press on a link shouldn't open a browser preview of an app page.
        webView.allowsLinkPreview = false
        #if DEBUG
            webView.isInspectable = true
        #endif
        return webView
    }
}

/// A web screen's title is its page's `<title>`, kept in step as it changes.
/// Hotwire Native reads the title once, when Turbo says a visit rendered, and
/// WebKit can still report the previous page's title then: a sheet that
/// reused its web view showed "Move to project" over New chat. The screen
/// holding the web view follows the title instead, including a page that
/// retitles itself later.
enum PageTitle {
    private nonisolated(unsafe) static var key: UInt8 = 0

    static func follow(_ webView: WKWebView) {
        let observation = webView.observe(\.title, options: [.new]) { webView, _ in
            MainActor.assumeIsolated {
                // Turbo swaps <title> elements while it renders, which passes
                // through an empty title.
                guard let title = webView.title, !title.isEmpty, let screen = webView.visitableViewController else { return }
                screen.navigationItem.title = title
            }
        }
        objc_setAssociatedObject(webView, &key, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// A page starts whole, however far someone pinched the one before it.
/// Turbo keeps the document from page to page, and WebKit keeps its zoom
/// with it, so a file's pages zoomed in the viewer left the next sheet in
/// the same web view (another file, Settings) zoomed in too. A file's
/// viewer also resets it as it goes (FileShareComponent), for the same file
/// opened again, whose address doesn't change.
enum PinchZoom {
    private nonisolated(unsafe) static var key: UInt8 = 0

    static func resetOnNewPage(_ webView: WKWebView) {
        let observation = webView.observe(\.url, options: [.old, .new]) { webView, change in
            MainActor.assumeIsolated {
                guard let old = change.oldValue.flatMap({ $0 }), let new = change.newValue.flatMap({ $0 }),
                      old.path != new.path else { return }
                reset(webView)
            }
        }
        objc_setAssociatedObject(webView, &key, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func reset(_ webView: WKWebView?) {
        guard let scrollView = webView?.scrollView, scrollView.zoomScale > scrollView.minimumZoomScale + 0.001 else { return }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
    }
}

/// Tells the app when a page has painted, so its skeleton can go
/// (PageSkeleton): a page loaded from scratch says so at its first
/// contentful paint, a Turbo visit in the frame after it renders. Each
/// message carries the page's path and query, and when the paint happened
/// (`at`, milliseconds since 1970), both taken as it happens rather than
/// when the message goes two frames later, by which time a newer visit
/// may have moved the web view on.
enum PagePaint {
    static let handlerName = "cwwPagePaint"

    static let script = """
    (() => {
      const now = () => ({ path: location.pathname + location.search, at: Date.now() })
      const say = (page) => {
        try { window.webkit.messageHandlers.\(handlerName).postMessage(page) } catch (_) {}
      }
      const afterFrame = () => { const page = now(); requestAnimationFrame(() => requestAnimationFrame(() => say(page))) }
      let painted = false
      const paint = () => { if (!painted) { painted = true; say(now()) } }
      if (window.PerformanceObserver && (PerformanceObserver.supportedEntryTypes || []).includes("paint")) {
        new PerformanceObserver((list) => {
          if (list.getEntries().some((entry) => entry.name === "first-contentful-paint")) paint()
        }).observe({ type: "paint", buffered: true })
      } else {
        addEventListener("DOMContentLoaded", () => requestAnimationFrame(() => requestAnimationFrame(paint)))
      }
      addEventListener("turbo:render", afterFrame)
    })()
    """

    static func install(in configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(Handler(), name: handlerName)
    }

    private final class Handler: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let path = body["path"] as? String,
                  let webView = message.webView, let screen = webView.visitableViewController else { return }
            let at = (body["at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            PageSkeleton.pagePainted(path: path, at: at, webView: webView, on: screen)
        }
    }
}

private extension UIView {
    /// The web screen whose view holds this one, if it's on one.
    var visitableViewController: VisitableViewController? {
        sequence(first: self as UIResponder, next: \.next).lazy.compactMap { $0 as? VisitableViewController }.first
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
