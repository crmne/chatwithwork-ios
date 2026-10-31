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
    /// kind and `steps` how many it took so far. A wait for the person is an
    /// update with `phase` `approval_waiting` or `input_requested`, and the
    /// activity goes on after it. At the end, `phase` is `answered`, `failed`
    /// or `stopped`, and `message` generic words for it. `run`, `revision` and
    /// `startedAt` (unix seconds) say which answer that is and where it
    /// stands. Older servers send those, and the optionals after them, not
    /// at all. `service` and `services` are built-in keys, or `mcp` and
    /// `computer`, never a name a person gave one. `pace` says how long each
    /// step of `trail` took, a digit each.
    struct ContentState: Codable, Hashable, Sendable {
        var phase: String
        var message: String?
        var step: String?
        var steps: Int?
        var recentSteps: [String]?
        var run: String?
        var revision: Int64?
        var startedAt: Int64?
        var waitingSince: Int64?
        var service: String?
        var services: [String]?
        var trail: String?
        var pace: String?
        var agents: Int?
        var heardAt: Int64?

        enum CodingKeys: String, CodingKey {
            case phase, message, step, steps, run, revision, service, services, trail, pace, agents
            case recentSteps = "recent_steps"
            case startedAt = "started_at"
            case waitingSince = "waiting_since"
            case heardAt = "heard_at"
        }

        static let answering = ContentState(phase: "answering", message: nil)

        var isWorking: Bool { phase == "answering" }

        var needsAttention: Bool { phase == "approval_waiting" || phase == "input_requested" }

        /// The line the Live Activity shows for this phase.
        var line: String {
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return message }
            switch phase {
            case "answered": return String(localized: "Your answer is ready.")
            case "approval_waiting": return String(localized: "A change is waiting for your approval.")
            case "input_requested": return String(localized: "A question is waiting for your answer.")
            case "failed": return String(localized: "The answer couldn't finish.")
            case "stopped": return String(localized: "The answer stopped.")
            case "answering":
                switch step {
                case "search": return String(localized: "Searching")
                case "list": return String(localized: "Browsing")
                case "read": return String(localized: "Reading")
                case "plan": return String(localized: "Planning")
                case "run": return String(localized: "Running a task")
                case "ask": return String(localized: "Asking you to decide")
                case "write": return String(localized: "Writing the answer")
                case "use": return String(localized: "Using a tool")
                default: return String(localized: "Answering")
                }
            default: return String(localized: "Open chat for an update")
            }
        }
    }

    /// The organization's name, the one thing the activity names.
    var organization: String
    /// The chat's path on the server, which a tap opens.
    var path: String
    var startedAt: Date
    /// The answer this activity belongs to, which it keeps for its whole
    /// life; nil on an older server.
    var run: String? = nil
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
