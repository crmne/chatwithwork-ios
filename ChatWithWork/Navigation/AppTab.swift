import HotwireNative
import UIKit

/// The tab bar: three places and one action.
///
/// Chats, Projects and Settings each own a navigator, so going back and forth
/// between them keeps each one's stack. New chat is not a place: selecting it
/// opens the new chat page as a sheet over Chats (MainTabBarController).
nonisolated enum AppTab: String, CaseIterable, Sendable {
    case chats
    case projects
    case settings
    case newChat = "new-chat"

    static let destinations: [AppTab] = [.chats, .projects, .settings]

    var title: String {
        switch self {
        case .chats: String(localized: "Chats")
        case .projects: String(localized: "Projects")
        case .settings: String(localized: "Settings")
        case .newChat: String(localized: "New chat")
        }
    }

    /// The path inside an organization; the server redirects the unprefixed
    /// form into the organization the person used last.
    var path: String {
        switch self {
        case .chats: "/chats"
        case .projects: "/projects"
        case .settings: "/settings"
        case .newChat: "/chats/new"
        }
    }

    var isAction: Bool { self == .newChat }

    var image: UIImage? {
        UIImage(systemName: symbolName)
    }

    var selectedImage: UIImage? {
        UIImage(systemName: selectedSymbolName) ?? image
    }

    private var symbolName: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right"
        case .projects: "folder"
        case .settings: "gearshape"
        case .newChat: "square.and.pencil"
        }
    }

    private var selectedSymbolName: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right.fill"
        case .projects: "folder.fill"
        case .settings: "gearshape.fill"
        case .newChat: "square.and.pencil"
        }
    }

    /// The URL this tab starts at, inside `account` when the shell knows it.
    func url(in environment: AppEnvironment, account: AccountSlug?) -> URL {
        environment.url(path: Self.path(path, in: account))
    }

    static func path(_ path: String, in account: AccountSlug?) -> String {
        guard let account else { return path }
        return "/\(account.rawValue)\(path)"
    }
}
