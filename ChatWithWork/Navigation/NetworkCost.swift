import Network
import WebKit

/// What the network costs, for the pages, which load Decisions, New chat and
/// New bot ahead only on one that costs nothing (docs/server-contract.md,
/// "What the network costs"). WKWebView tells a page nothing about the
/// network, so the app keeps `window.chatWithWorkNetwork = {metered,
/// constrained}` current in every web view it shows pages in: a user script
/// at document start, so a page loading has it before its own scripts run,
/// and on every change to a page already open, which then may load ahead
/// (`window.chatWithWork?.preload?.()`). Until iOS first says, pages hear
/// nothing, and don't load ahead.
@MainActor
final class NetworkCost {
    static let shared = NetworkCost()

    struct Cost: Equatable, Sendable {
        /// Cellular or a personal hotspot.
        var metered: Bool
        /// Low Data Mode.
        var constrained: Bool

        var isFree: Bool { !metered && !constrained }
    }

    /// The cost `path` says: expensive is metered, constrained is Low Data Mode.
    nonisolated static func cost(expensive: Bool, constrained: Bool) -> Cost {
        Cost(metered: expensive, constrained: constrained)
    }

    nonisolated static let marker = "/* cww-network */"

    nonisolated static func script(_ cost: Cost) -> String {
        "\(marker) window.chatWithWorkNetwork = { metered: \(cost.metered), constrained: \(cost.constrained) };"
    }

    private(set) var cost: Cost?
    private let monitor = NWPathMonitor()
    private let webViews = NSHashTable<WKWebView>.weakObjects()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { @Sendable path in
            let cost = NetworkCost.cost(expensive: path.isExpensive, constrained: path.isConstrained)
            Task { @MainActor in NetworkCost.shared.update(cost) }
        }
        monitor.start(queue: DispatchQueue(label: "com.chatwithwork.network-cost"))
    }

    /// Keeps `webView`'s pages told, from the next page it loads on.
    func follow(_ webView: WKWebView) {
        webViews.add(webView)
        if let cost { install(cost, in: webView.configuration.userContentController) }
    }

    func update(_ cost: Cost) {
        guard cost != self.cost else { return }
        self.cost = cost
        for webView in webViews.allObjects {
            install(cost, in: webView.configuration.userContentController)
            // Told now, a page that may load ahead does.
            webView.evaluateJavaScript(Self.script(cost) + (cost.isFree ? " window.chatWithWork?.preload?.();" : "") + " 0", completionHandler: nil)
        }
    }

    /// For pages loaded from now on. Earlier scripts stay, as TextSize's do:
    /// the latest runs last and wins.
    private func install(_ cost: Cost, in controller: WKUserContentController) {
        let latest = controller.userScripts.last { $0.source.hasPrefix(Self.marker) }
        guard latest?.source != Self.script(cost) else { return }
        controller.addUserScript(WKUserScript(source: Self.script(cost), injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
}
