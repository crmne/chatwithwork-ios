import ActivityKit
import Foundation

/// A Live Activity for an answer still working after the person left the
/// chat: the organization, how long it has been answering, and how it ended.
/// Never the chat's title or anything from it (docs/server-contract.md,
/// "Live Activities"). Shared by the app, which starts it, and the widget
/// extension, which draws it.
nonisolated struct ChatActivityAttributes: ActivityAttributes {
    /// What the server's end push says: `phase` is `answered`,
    /// `approval_waiting`, `input_requested` or `failed`, and `message`
    /// generic words for it. While it works, `phase` is `answering`.
    struct ContentState: Codable, Hashable, Sendable {
        var phase: String
        var message: String?

        static let answering = ContentState(phase: "answering", message: nil)

        var isWorking: Bool { phase == "answering" }

        /// The line the Live Activity shows for this phase.
        var line: String {
            if let message, !message.isEmpty { return message }
            switch phase {
            case "answered": return String(localized: "Your answer is ready.")
            case "approval_waiting": return String(localized: "A change is waiting for your approval.")
            case "input_requested": return String(localized: "A question is waiting for your answer.")
            case "failed": return String(localized: "The answer couldn't finish.")
            default: return String(localized: "Answering")
            }
        }
    }

    /// The organization's name, the one thing the activity names.
    var organization: String
    /// The chat's path on the server, which a tap opens.
    var path: String
    var startedAt: Date
}

/// The app's own links, which widgets, Live Activities and the share
/// extension open: `chatwithwork://new-chat` (with `dictate=1`, or the
/// shared `title`, `text`, `url`, and `shared` files' folder) and
/// `chatwithwork://open?path=/482139075/chats/42`.
nonisolated enum AppLink {
    static let scheme = "chatwithwork"

    static func newChat(dictate: Bool = false, title: String? = nil, text: String? = nil, url: String? = nil, shared: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "new-chat"
        let items = [
            dictate ? URLQueryItem(name: "dictate", value: "1") : nil,
            title.map { URLQueryItem(name: "title", value: $0) },
            text.map { URLQueryItem(name: "text", value: $0) },
            url.map { URLQueryItem(name: "url", value: $0) },
            shared.map { URLQueryItem(name: "shared", value: $0) }
        ].compactMap { $0 }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    static func open(path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url!
    }
}
