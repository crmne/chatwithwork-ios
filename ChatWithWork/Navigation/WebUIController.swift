@preconcurrency import HotwireNative
import WebKit

/// The navigators' WebKit UI delegate: Hotwire Native's own (alerts,
/// confirms, links out of frames) plus the microphone for the web
/// composer's dictation, which records in the page. Hotwire Native means its
/// `WKUIController` to be subclassed for this; the screens themselves stay
/// plain `HotwireWebViewController`s.
nonisolated final class WebUIController: WKUIController {
    private let server: URL

    init(delegate: WKUIControllerDelegate, server: URL = AppEnvironment.current.baseURL) {
        self.server = server
        super.init(delegate: delegate)
    }

    /// The page's microphone, asked for by the composer's dictation: granted
    /// without WebKit's own prompt for this server's pages in the main
    /// frame, so the person answers iOS's prompt once and not a second one
    /// every time; the camera, and anything another origin or a frame asks
    /// for, is refused.
    @objc(webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(Self.decision(scheme: origin.protocol, host: origin.host, port: origin.port, isMainFrame: frame.isMainFrame, type: type, server: server))
    }

    /// `port` is WebKit's: 0 for the scheme's default.
    static func decision(scheme: String, host: String, port: Int, isMainFrame: Bool, type: WKMediaCaptureType, server: URL) -> WKPermissionDecision {
        guard type == .microphone, isMainFrame,
              scheme.lowercased() == server.scheme?.lowercased(),
              host.lowercased() == server.host()?.lowercased(),
              port == (server.port ?? 0)
        else { return .deny }
        return .grant
    }
}
