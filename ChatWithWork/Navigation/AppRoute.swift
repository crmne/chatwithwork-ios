import Foundation

/// An organization's external id, the first segment of every page inside it:
/// `/482139075/chats/42`. Rails (`AccountSlug::PATTERN`) accepts seven digits
/// or more.
nonisolated struct AccountSlug: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init?(_ rawValue: some StringProtocol) {
        guard rawValue.count >= 7, rawValue.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        self.rawValue = String(rawValue)
    }

    var description: String { rawValue }
}

/// What a location on the server is, as far as the native shell cares.
///
/// Every page inside an organization lives under its slug, so the shell
/// strips it before classifying and keeps it to notice when someone moves to
/// another organization.
nonisolated struct AppRoute: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A tab's root list: `/chats`, `/projects`, `/settings`.
        case tabRoot(AppTab)
        case newChat
        case chat(number: Int)
        /// Sign in, sign up, password and confirmation pages.
        case authentication
        /// Turbo's `recede_`, `resume_` and `refresh_historical_location`.
        case historicalLocation(HistoricalLocation)
        /// Uploaded files and generated previews (Active Storage).
        case file
        case other
    }

    enum HistoricalLocation: String, Sendable {
        case recede
        case resume
        case refresh
    }

    let account: AccountSlug?
    /// The path without the organization prefix, always starting with "/".
    let path: String
    let kind: Kind

    init(url: URL) {
        self.init(path: url.path(percentEncoded: false))
    }

    init(path rawPath: String) {
        var segments = rawPath.split(separator: "/", omittingEmptySubsequences: true)
        if let first = segments.first, let slug = AccountSlug(first) {
            account = slug
            segments.removeFirst()
        } else {
            account = nil
        }

        path = "/" + segments.joined(separator: "/")
        kind = Self.classify(segments.map(String.init))
    }

    var isSignIn: Bool { kind == .authentication && path == "/users/sign_in" }

    var isAuthentication: Bool { kind == .authentication }

    /// The tab this location belongs to when the shell routes it from outside
    /// a tab (a universal link or a notification).
    var preferredTab: AppTab? {
        switch kind {
        case .tabRoot(let tab): tab
        case .newChat, .chat: .chats
        default:
            if path.hasPrefix("/projects") { .projects }
            else if path.hasPrefix("/settings") { .settings }
            else if path.hasPrefix("/chats") { .chats }
            else { nil }
        }
    }

    private static func classify(_ segments: [String]) -> Kind {
        switch segments.count {
        case 0:
            return .other
        case 1:
            switch segments[0] {
            case "chats": return .tabRoot(.chats)
            case "projects": return .tabRoot(.projects)
            case "settings": return .tabRoot(.settings)
            case "users": return .authentication // a sign-up form re-rendered after a failed POST
            case "recede_historical_location": return .historicalLocation(.recede)
            case "resume_historical_location": return .historicalLocation(.resume)
            case "refresh_historical_location": return .historicalLocation(.refresh)
            default: return .other
            }
        default:
            break
        }

        if segments[0] == "users" {
            let authentication: Set<String> = ["sign_in", "sign_up", "password", "confirmation", "unlock"]
            return authentication.contains(segments[1]) ? .authentication : .other
        }

        if segments[0] == "rails", segments[1] == "active_storage" {
            return .file
        }

        if segments[0] == "chats", segments.count == 2 {
            if segments[1] == "new" { return .newChat }
            if let number = Int(segments[1]) { return .chat(number: number) }
        }

        return .other
    }
}
