import Foundation

/// The little the app remembers between launches about the session the web
/// views hold: whether someone signed in, which organization they were in,
/// the list the sidebar showed there, and the chat they left last. The session itself is the server's cookie in the shared web data
/// store; this only decides what to show before the first page answers.
struct SessionMemory {
    static let standard = SessionMemory(defaults: .standard)

    let defaults: UserDefaults

    private enum Key {
        static let hasSignedIn = "CWWHasSignedIn"
        static let lastAccount = "CWWLastAccount"
        static let listKeys = "CWWSidebarLists"
        static let newChatPaths = "CWWNewChatPaths"
        static let lastChat = "CWWLastChat"
        static let lastChatAt = "CWWLastChatAt"
    }

    var hasSignedIn: Bool {
        get { defaults.bool(forKey: Key.hasSignedIn) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasSignedIn) }
    }

    var lastAccount: AccountSlug? {
        get { defaults.string(forKey: Key.lastAccount).flatMap(AccountSlug.init) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Key.lastAccount) }
    }

    /// The list the sidebar shows in each organization (a ChatList key).
    func listKey(in account: AccountSlug) -> String? {
        (defaults.dictionary(forKey: Key.listKeys) as? [String: String])?[account.rawValue]
    }

    func setListKey(_ key: String?, in account: AccountSlug) {
        var keys = (defaults.dictionary(forKey: Key.listKeys) as? [String: String]) ?? [:]
        keys[account.rawValue] = key
        defaults.set(keys, forKey: Key.listKeys)
    }

    /// Where New chat leads in each organization: into the list's project, if
    /// it shows one. The app opens there.
    func newChatPath(in account: AccountSlug) -> String? {
        (defaults.dictionary(forKey: Key.newChatPaths) as? [String: String])?[account.rawValue]
    }

    func setNewChatPath(_ path: String, in account: AccountSlug) {
        var paths = (defaults.dictionary(forKey: Key.newChatPaths) as? [String: String]) ?? [:]
        paths[account.rawValue] = path
        defaults.set(paths, forKey: Key.newChatPaths)
    }

    /// The chat on screen when the person last left one, and when.
    var lastChat: (path: String, at: Date)? {
        get {
            guard let path = defaults.string(forKey: Key.lastChat), let at = defaults.object(forKey: Key.lastChatAt) as? Date else { return nil }
            return (path, at)
        }
        nonmutating set {
            defaults.set(newValue?.path, forKey: Key.lastChat)
            defaults.set(newValue?.at, forKey: Key.lastChatAt)
        }
    }

    func reset() {
        [Key.hasSignedIn, Key.lastAccount, Key.listKeys, Key.newChatPaths, Key.lastChat, Key.lastChatAt].forEach(defaults.removeObject(forKey:))
    }
}
