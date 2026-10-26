import Foundation
import Testing
import UserNotifications
@testable import ChatWithWork

/// What a notification says, fetched from the server as it arrives by the
/// notification service extension (docs/server-contract.md, "Push
/// notifications"), with the phone's notification key.
@Suite("Notification words")
struct NotificationWordsTests {
    private let key = NotificationKey.Stored(key: "eyJfcmFpbHMiOnt9fQ==--abc123", token: "a1b2", baseURL: URL(string: "https://chatwithwork.com")!)

    @Test("asks this server for the id's words, with the phone's key as a bearer token")
    func request() throws {
        let request = try #require(NotificationWords.request(for: "c2VjcmV0--aXY--dGFn_x-y", with: key))

        #expect(request.url?.absoluteString == "https://chatwithwork.com/native/notifications/c2VjcmV0--aXY--dGFn_x-y")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer eyJfcmFpbHMiOnt9fQ==--abc123")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.timeoutInterval == NotificationWords.timeout)
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test("takes only an id shaped like the server's, never a path")
    func refusesOtherIDs() {
        #expect(NotificationWords.request(for: "", with: key) == nil)
        #expect(NotificationWords.request(for: "../../settings", with: key) == nil)
        #expect(NotificationWords.request(for: "abc?x=1", with: key) == nil)
        #expect(NotificationWords.request(for: "abc/def", with: key) == nil)
        #expect(NotificationWords.request(for: "ébc", with: key) == nil)
    }

    @Test("decodes the server's words, with or without a subtitle")
    func decodes() throws {
        let answer = try JSONDecoder().decode(NotificationWords.Text.self, from: Data(#"{"title":"Q3 numbers","body":"Revenue grew 12%."}"#.utf8))
        #expect(answer == NotificationWords.Text(title: "Q3 numbers", subtitle: nil, body: "Revenue grew 12%."))

        let wait = try JSONDecoder().decode(NotificationWords.Text.self, from: Data(#"{"title":"Acme launch","subtitle":"Waiting for your approval in Slack","body":"Post the recap"}"#.utf8))
        #expect(wait.subtitle == "Waiting for your approval in Slack")
    }

    @Test("puts the words in place of the push's own, keeping everything else")
    func rewrites() throws {
        let arrived = UNMutableNotificationContent()
        arrived.title = "Northwind Studio"
        arrived.body = "A change is waiting for your approval in Slack."
        arrived.threadIdentifier = "chat-482139075-42"
        arrived.categoryIdentifier = "approval_waiting"
        arrived.userInfo = ["path": "/482139075/chats/42", "notification_id": "abc"]

        let shown = NotificationWords.content(arrived, saying: NotificationWords.Text(title: "Acme launch", subtitle: "Waiting for your approval in Slack", body: "Post the launch recap to #acme-launch"))

        #expect(shown.title == "Acme launch")
        #expect(shown.subtitle == "Waiting for your approval in Slack")
        #expect(shown.body == "Post the launch recap to #acme-launch")
        #expect(shown.threadIdentifier == "chat-482139075-42")
        #expect(shown.categoryIdentifier == "approval_waiting")
        #expect(shown.userInfo["path"] as? String == "/482139075/chats/42")
    }

    @Test("a fetch that fails or doesn't answer 200 leaves the push's own words")
    func failsQuietly() async {
        let unreachable = NotificationKey.Stored(key: "k", token: "t", baseURL: URL(string: "http://127.0.0.1:9")!)
        #expect(await NotificationWords.fetch("abc", with: unreachable) == nil)
    }

    @Test("every kind the server sends hides its words behind what happened")
    func categories() {
        let categories = PushNotifications.categories
        for kind in ["answered", "approval_waiting", "input_requested", "handed_off", "failed", "decisions_waiting"] {
            let category = categories.first { $0.identifier == kind }
            #expect(category != nil, "\(kind)")
            #expect(category?.hiddenPreviewsBodyPlaceholder.isEmpty == false, "\(kind)")
        }
    }

    @Test("needs a key until it has one for this token on this server")
    @MainActor
    func needsKey() {
        let push = PushNotifications.shared
        NotificationKey.delete()
        defer { NotificationKey.delete() }

        #expect(!push.needsKey(for: nil))
        #expect(push.needsKey(for: "a1b2"))

        push.keep(key: "the-key", for: "a1b2")
        if NotificationKey.load() != nil {
            #expect(!push.needsKey(for: "a1b2"))
            #expect(push.needsKey(for: "c3d4"), "a new token needs a new key")
            push.forgetKey()
            #expect(push.needsKey(for: "a1b2"))
        }
    }
}
