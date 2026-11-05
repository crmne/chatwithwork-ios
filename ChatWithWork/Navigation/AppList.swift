import Foundation

/// The lists the shell knows by their path: the places a sidebar row or a
/// link from outside leads to. None is a tab any more (the sidebar replaced
/// the tab bar); each replaces the root screen (the path configuration's
/// `replace_root`, Places).
nonisolated enum AppList: String, CaseIterable, Sendable {
    case chats
    case projects
    case bots
    case settings

    /// The path inside an organization.
    var path: String { "/\(rawValue)" }
}

nonisolated enum AppPath {
    /// The new chat page, where the app opens.
    static let newChat = "/chats/new"

    /// `path` inside `account` when the shell knows it; the server redirects
    /// the unprefixed form into the organization the person used last.
    static func path(_ path: String, in account: AccountSlug?) -> String {
        guard let account else { return path }
        return "/\(account.rawValue)\(path)"
    }
}
