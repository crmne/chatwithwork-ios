import Foundation

/// The little the app remembers between launches about the session the web
/// views hold: whether someone signed in, and which organization they were
/// in. The session itself is the server's cookie in the shared web data
/// store; this only decides what to show before the first page answers.
struct SessionMemory {
    static let standard = SessionMemory(defaults: .standard)

    let defaults: UserDefaults

    private enum Key {
        static let hasSignedIn = "CWWHasSignedIn"
        static let lastAccount = "CWWLastAccount"
    }

    var hasSignedIn: Bool {
        get { defaults.bool(forKey: Key.hasSignedIn) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasSignedIn) }
    }

    var lastAccount: AccountSlug? {
        get { defaults.string(forKey: Key.lastAccount).flatMap(AccountSlug.init) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Key.lastAccount) }
    }

    func reset() {
        defaults.removeObject(forKey: Key.hasSignedIn)
        defaults.removeObject(forKey: Key.lastAccount)
    }
}
