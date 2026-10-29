import ActivityKit
import Foundation

/// A Live Activity for an answer still working after the person left the
/// chat: the organization, what the answer is doing and how long it has
/// been at it, and how it ended. Never the chat's title or anything from it
/// (docs/server-contract.md, "Live Activities"). Shared by the app, which
/// starts it, and the widget extension, which draws it.
nonisolated struct ChatActivityAttributes: ActivityAttributes {
    /// What the server's pushes say. While the answer works, `phase` is
    /// `answering`, `message` the step it's on in words that carry nothing
    /// from the chat ("Searching Todoist", "Writing the answer"), `step` its
    /// kind and `steps` how many it took so far. At the end, `phase` is
    /// `answered`, `approval_waiting`, `input_requested`, `failed` or
    /// `stopped`, and `message` generic words for it.
    struct ContentState: Codable, Hashable, Sendable {
        var phase: String
        var message: String?
        var step: String?
        var steps: Int?

        static let answering = ContentState(phase: "answering", message: nil)

        var isWorking: Bool { phase == "answering" }

        /// Stale content must never suggest the answer is still progressing.
        func showsElapsed(isStale: Bool) -> Bool { isWorking && !isStale }

        /// Compact headlines fit the Island without truncating the decision.
        var headline: String {
            switch phase {
            case "answering": line
            case "answered": String(localized: "Answer ready")
            case "approval_waiting": String(localized: "Approval needed")
            case "input_requested": String(localized: "Your input needed")
            case "failed": String(localized: "Couldn't finish")
            case "stopped": String(localized: "Stopped")
            default: String(localized: "Open chat for an update")
            }
        }

        var action: String {
            switch phase {
            case "approval_waiting": String(localized: "Review change")
            case "input_requested": String(localized: "Reply")
            case "answered": String(localized: "Read answer")
            default: String(localized: "Open chat")
            }
        }

        var needsAttention: Bool { phase == "approval_waiting" || phase == "input_requested" }

        /// The line the Live Activity shows for this phase.
        var line: String {
            if let message, !message.isEmpty { return message }
            switch phase {
            case "answered": return String(localized: "Your answer is ready.")
            case "approval_waiting": return String(localized: "A change is waiting for your approval.")
            case "input_requested": return String(localized: "A question is waiting for your answer.")
            case "failed": return String(localized: "The answer couldn't finish.")
            case "stopped": return String(localized: "The answer stopped.")
            default: return String(localized: "Answering")
            }
        }

        /// The SF Symbol for the step it's on, or for how it ended.
        var symbol: String {
            switch phase {
            case "answering":
                switch step {
                case "search": "magnifyingglass"
                case "list": "folder"
                case "read": "doc.text"
                case "plan": "checklist"
                case "run": "terminal"
                case "ask": "questionmark.bubble"
                case "write": "text.alignleft"
                case "use": "wrench.and.screwdriver"
                default: "ellipsis"
                }
            case "answered": "checkmark.circle.fill"
            case "approval_waiting", "input_requested": "hand.raised.fill"
            case "failed": "exclamationmark.triangle.fill"
            default: "stop.circle.fill"
            }
        }

        /// Includes a step still running, so never call these completed steps.
        var stepsLine: String? {
            guard let steps, steps > 0 else { return nil }
            return steps == 1
                ? String(localized: "1 step so far", comment: "Includes the step currently running")
                : String(localized: "\(steps) steps so far", comment: "Includes the step currently running")
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
