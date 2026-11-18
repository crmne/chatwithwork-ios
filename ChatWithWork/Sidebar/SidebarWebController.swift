import UIKit
import WebKit

/// The drawer's web view of the sidebar page (docs/server-contract.md, "The
/// sidebar page"): kept loaded beside the navigator for as long as the shell
/// lives, so it opens at once and stays live on the page's own streams.
///
/// It never navigates away from the page: whatever would (a row, New chat,
/// Decisions, a form's redirect, a link Turbo doesn't follow) goes to the
/// shell through `onVisit` or `onExternal`. It's shown only once the page
/// says it's drawn (`ready`); until then, and when the page fails before
/// ever showing, the shell's native sidebar shows instead.
final class SidebarWebController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var onReady: (() -> Void)?
    var onVisit: ((URL) -> Void)?
    var onExternal: ((URL) -> Void)?
    var onClose: (() -> Void)?
    /// No session: `true` when the page led to the sign-in form (signing
    /// out from the person's menu), `false` when its own load found none.
    var onSignedOut: ((Bool) -> Void)?
    /// The server doesn't know the page (404), or it failed before showing.
    var onUnavailable: (() -> Void)?

    private(set) var isReady = false
    private(set) var pageURL: URL?
    private var current: (url: URL, belongsTo: String?)?

    private let environment: AppEnvironment
    private var webView: WKWebView!

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = SidebarPage.userAgent(prefix: environment.userAgentPrefix)
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.dataDetectorTypes = []
        // Kept to the app-bound domains like the navigator's web views, so the
        // pages' service worker runs here too and keeps the page offline.
        configuration.limitsNavigationsToAppBoundDomains = AppBoundDomains.covers(environment.baseURL)
        configuration.userContentController.add(MessageProxy(self), name: "sidebar")
        configuration.userContentController.addUserScript(WKUserScript(source: SidebarPage.staleScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.accessibilityIdentifier = "sidebar.page"
        webView.allowsBackForwardNavigationGestures = false
        // The page never scrolls; its list does, inside it. No bounce, no zoom.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        // No white flash before the first paint in dark mode.
        webView.isOpaque = false
        webView.backgroundColor = Palette.canvasSunken
        webView.scrollView.backgroundColor = Palette.canvasSunken
        webView.underPageBackgroundColor = Palette.canvasSunken
        TextSize.follow(webView)
        #if DEBUG
            webView.isInspectable = true
        #endif
        self.webView = webView
        view = webView
    }

    // MARK: What the shell asks

    /// Loads the page at `url`, unless it's the one loaded already.
    func load(_ url: URL) {
        loadViewIfNeeded()
        guard url != pageURL else { return }
        pageURL = url
        isReady = false
        webView.load(URLRequest(url: url))
    }

    /// Stops showing the page: the server named none.
    func unload() {
        guard pageURL != nil else { return }
        pageURL = nil
        isReady = false
        webView?.stopLoading()
    }

    /// The page on the app's screen, whose row the page marks.
    func setCurrent(_ url: URL, belongsTo: String?) {
        current = (url, belongsTo)
        if isReady { webView.evaluateJavaScript(SidebarPage.currentScript(url: url, belongsTo: belongsTo)) }
    }

    /// Draws the page again, back from the background, where its streams
    /// may have missed something.
    func refresh() {
        if isReady { webView.evaluateJavaScript(SidebarPage.refreshScript) }
    }

    // MARK: What the page says

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let origin = message.frameInfo.request.url, environment.owns(origin),
              let parsed = SidebarPage.Message(body: message.body, base: environment.baseURL)
        else { return }

        switch parsed {
        case .ready:
            isReady = true
            if let current { webView.evaluateJavaScript(SidebarPage.currentScript(url: current.url, belongsTo: current.belongsTo)) }
            onReady?()
        case .visit(let url):
            go(to: url)
        case .close:
            onClose?()
        case .confirm(let confirm):
            ask(confirm)
        case .stale:
            // Drawn again with a fresh token; it stays on screen meanwhile.
            webView.reload()
        }
    }

    private func go(to url: URL) {
        switch SidebarPage.destination(of: url, page: pageURL, environment: environment) {
        case .page, .ignore: break
        case .place(let url): onVisit?(url)
        case .signedOut: onSignedOut?(true)
        case .external(let url): onExternal?(url)
        }
    }

    /// Turbo's confirm, as the app's own alert, worded as the page says.
    private func ask(_ confirm: SidebarPage.Message.Confirm) {
        let alert = UIAlertController(title: confirm.title, message: confirm.description, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: confirm.dismiss, style: .cancel) { [weak self] _ in self?.answer(confirm.id, false) })
        alert.addAction(UIAlertAction(title: confirm.confirm, style: confirm.destructive ? .destructive : .default) { [weak self] _ in self?.answer(confirm.id, true) })
        presenter.present(alert, animated: true)
    }

    private func answer(_ id: String, _ confirmed: Bool) {
        webView.evaluateJavaScript(SidebarPage.answerScript(id: id, confirmed: confirmed))
    }

    private var presenter: UIViewController {
        var top: UIViewController = parent ?? self
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame ?? true, let url = navigationAction.request.url else { return .allow }
        switch SidebarPage.destination(of: url, page: pageURL, environment: environment) {
        case .page:
            return .allow
        case .ignore:
            return url.scheme == "about" ? .allow : .cancel
        case .place(let url):
            onVisit?(url)
        case .signedOut:
            onSignedOut?(navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .formSubmitted)
        case .external(let url):
            onExternal?(url)
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse else { return .allow }
        switch response.statusCode {
        case 200..<400:
            return .allow
        case 401:
            onSignedOut?(false)
        default:
            // 404: a server without the page. Anything else: try again on
            // the next connect, the native sidebar meanwhile.
            fail()
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { fail() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { fail() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        webView.reload()
    }

    /// A page that never showed hands the drawer back to the native sidebar,
    /// and the next connect tries it again; one that showed stays as it was.
    private func fail() {
        guard !isReady else { return }
        pageURL = nil
        onUnavailable?()
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { go(to: url) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in continuation.resume(returning: true) })
            presenter.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in continuation.resume() })
            presenter.present(alert, animated: true)
        }
    }
}

/// WebKit keeps its script message handlers strongly; this keeps the web
/// view's controller weakly, so the drawer goes with its shell.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: SidebarWebController?

    init(_ target: SidebarWebController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.receive(message) }
    }
}
