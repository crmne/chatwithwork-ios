import Foundation

/// The sidebar page (docs/server-contract.md, "The sidebar page"): the web
/// sidebar's own column, which servers that know it name in the `sidebar`
/// component's `connect` as `page`, and which the shell keeps loaded in a web
/// view of its own in the drawer (`SidebarWebController`). What it shows
/// changes with the server, never with an app release. Everything here is
/// the logic, with no web view, so it's tested on its own.
nonisolated enum SidebarPage {
    /// What a page's `sidebar` component says in its `connect`. An older
    /// server sends neither key, and the native sidebar stays.
    struct Connect: Decodable, Equatable, Sendable {
        let page: String?
        let belongsTo: String?

        init(page: String?, belongsTo: String?) {
            self.page = page
            self.belongsTo = belongsTo
        }

        /// The page's path, if it's one of this server's: a path, never a
        /// host of its own.
        var pagePath: String? {
            guard let page, page.hasPrefix("/"), !page.hasPrefix("//") else { return nil }
            return page
        }
    }

    /// The sidebar page's web view introduces itself as the app, so the
    /// server draws it for a phone (`data-native-app`), but lists no bridge
    /// components: none of the page's bridge controllers load where nothing
    /// would answer them, and Turbo's confirm comes to the app as a message.
    static func userAgent(prefix: String) -> String {
        prefix
    }

    /// What a connect means for the drawer.
    enum Choice: Equatable, Sendable {
        /// Load this path: a first page, or another organization's.
        case load(String)
        /// The page already loaded is the one named.
        case keep
        /// The server named none: the native sidebar.
        case native
    }

    static func choose(_ connect: Connect, loaded: String?) -> Choice {
        guard let path = connect.pagePath else { return .native }
        return path == loaded ? .keep : .load(path)
    }

    /// Where a navigation the web view was about to make goes instead.
    enum Destination: Equatable, Sendable {
        /// The sidebar page itself, drawn again: it may load.
        case page
        /// A page of this server: the navigator opens it as a place.
        case place(URL)
        /// The sign-in form: the session has gone.
        case signedOut
        /// Another site: the system opens it.
        case external(URL)
        /// Nothing to do (about:blank, a scheme nobody handles).
        case ignore
    }

    static func destination(of url: URL, page: URL?, environment: AppEnvironment) -> Destination {
        if url.scheme == "about" { return .ignore }
        guard environment.owns(url) else {
            let scheme = url.scheme?.lowercased()
            return scheme == "https" || scheme == "http" || scheme == "mailto" || scheme == "tel" ? .external(url) : .ignore
        }
        if let page, url.path(percentEncoded: false) == page.path(percentEncoded: false) { return .page }
        if AppRoute(url: url).isSignIn { return .signedOut }
        return .place(url)
    }

    /// Whether an outside link opens in Safari's sheet (web pages) rather
    /// than in the app that owns its scheme (`mailto:`, `tel:`).
    static func opensInSafariSheet(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "http"
    }

    /// A message the page posted (`window.webkit.messageHandlers.sidebar`).
    enum Message: Equatable, Sendable {
        case ready
        case visit(URL)
        case close
        case confirm(Confirm)
        /// One of the page's own requests answered 422 (posted by the app's
        /// `staleScript`, not the page): its CSRF token went stale.
        case stale

        struct Confirm: Equatable, Sendable {
            let id: String
            let title: String
            let description: String?
            let confirm: String
            let dismiss: String
            let destructive: Bool
        }

        init?(body: Any, base: URL) {
            guard let body = body as? [String: Any], let event = body["event"] as? String else { return nil }
            switch event {
            case "ready":
                self = .ready
            case "close":
                self = .close
            case "stale":
                self = .stale
            case "visit":
                guard let string = body["url"] as? String, let url = URL(string: string, relativeTo: base)?.absoluteURL else { return nil }
                self = .visit(url)
            case "confirm":
                guard let id = body["id"] as? String else { return nil }
                let text = { (key: String) in (body[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
                self = .confirm(Confirm(
                    id: id,
                    title: text("title") ?? "",
                    description: text("description"),
                    confirm: text("confirm") ?? String(localized: "OK"),
                    dismiss: text("dismiss") ?? String(localized: "Cancel"),
                    destructive: body["destructive"] as? Bool ?? false
                ))
            default:
                return nil
            }
        }
    }

    /// The script that tells the page which page is on the app's screen.
    static func currentScript(url: URL, belongsTo: String?) -> String {
        "window.chatWithWorkSidebar?.current(\(jsonString(url.absoluteString)), \(belongsTo.map(jsonString) ?? "null"))"
    }

    static func answerScript(id: String, confirmed: Bool) -> String {
        "window.chatWithWorkSidebar?.answer(\(jsonString(id)), \(confirmed))"
    }

    static let refreshScript = "window.chatWithWorkSidebar?.refresh()"

    /// In the main web view as the drawer opens: its page loads Decisions,
    /// New chat and New bot ahead, if the network allows (NetworkCost).
    static let preloadScript = "window.chatWithWork?.preload?.(); 0"

    /// The drawer closed. `closed` is newer than the page's other calls, so
    /// an older page without it is left alone.
    static let closedScript = "window.chatWithWorkSidebar?.closed?.()"

    /// The app's own script in the sidebar page: a request the page makes in
    /// place (a pin, a section, the filter) that answers 422 means its CSRF
    /// token went stale while it stayed loaded (signed in again, the session
    /// rotated). It says so, and the app loads the page again.
    static let staleScript = """
    document.addEventListener("turbo:before-fetch-response", function (event) {
      var response = event.detail && event.detail.fetchResponse
      if (response && response.statusCode === 422 && window.webkit && window.webkit.messageHandlers.sidebar) {
        window.webkit.messageHandlers.sidebar.postMessage({ event: "stale" })
      }
    })
    """

    private static func jsonString(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [string])) ?? Data("[\"\"]".utf8)
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }
}
