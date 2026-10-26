import Foundation
import Security
import UserNotifications

/// What a notification says, fetched from the server as it arrives, so the
/// chat's words never pass through Apple's push service (docs/server-contract.md,
/// "Push notifications"). The push carries `notification_id`, an id the app
/// can't read; the notification service extension asks the server for its
/// words with the phone's notification key, which the page handed the app
/// when it registered the token (`notification-token`'s `key`), and shows
/// the push's own words if that fails or takes too long.
nonisolated enum NotificationWords {
    /// `GET /native/notifications/:id`'s answer.
    struct Text: Decodable, Equatable, Sendable {
        let title: String
        let subtitle: String?
        let body: String
    }

    /// How long the extension waits before it shows the push's own words.
    /// iOS gives it about 30 seconds; a notification shouldn't wait that long.
    static let timeout: TimeInterval = 8

    static func request(for id: String, with key: NotificationKey.Stored) -> URLRequest? {
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }), id.unicodeScalars.allSatisfy(\.isASCII) else { return nil }

        var request = URLRequest(url: key.baseURL.appending(path: "native/notifications/\(id)"), cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.setValue("Bearer \(key.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// The push as it came, saying `text` instead: the chat's title, what
    /// waits as the subtitle, and the answer's start or what's to decide.
    static func content(_ arrived: UNNotificationContent, saying text: Text) -> UNNotificationContent {
        guard let content = arrived.mutableCopy() as? UNMutableNotificationContent else { return arrived }
        content.title = text.title
        content.subtitle = text.subtitle ?? ""
        content.body = text.body
        return content
    }

    /// The words for the notification `id` names, or nil: no key, an answer
    /// other than 200, or nothing in time.
    static func fetch(_ id: String, with key: NotificationKey.Stored, session: URLSession = .shared) async -> Text? {
        guard let request = request(for: id, with: key),
              let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = try? JSONDecoder().decode(Text.self, from: data),
              !text.title.isEmpty, !text.body.isEmpty
        else { return nil }
        return text
    }
}

/// The phone's notification key, in the keychain group the app shares with
/// its notification service extension (both list it first in their
/// keychain-access-groups, so it's where their items go by default), readable
/// after the phone's first unlock, so a notification arriving on a locked
/// phone can use it, and never in a backup.
nonisolated enum NotificationKey {
    struct Stored: Codable, Equatable, Sendable {
        /// The key, a bearer token for `GET /native/notifications/:id`.
        let key: String
        /// The push token it was issued for: a new token needs a new key.
        let token: String
        /// The server the app talks to, which the extension can't tell from
        /// its own Info.plist when a development build was pointed elsewhere.
        let baseURL: URL
    }

    private static let service = "com.chatwithwork.notification-key"
    private static let account = "key"

    static func load() -> Stored? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    @discardableResult
    static func save(_ stored: Stored) -> Bool {
        guard let data = try? JSONEncoder().encode(stored) else { return false }

        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            return SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
