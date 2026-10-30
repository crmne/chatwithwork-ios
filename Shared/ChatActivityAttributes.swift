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
        var recentSteps: [String]?

        enum CodingKeys: String, CodingKey {
            case phase, message, step, steps
            case recentSteps = "recent_steps"
        }

        /// Observed work only. Older servers supply just the current step.
        /// Returned tools may have failed or been declined; this is not a
        /// completion pipeline and must never receive success checkmarks.
        var recentActivityKinds: [String] {
            let known = Set(["search", "list", "read", "use", "plan", "run", "ask", "write", "answer"])
            var observed = recentSteps ?? []
            if let step, known.contains(step) { observed.append(step) }
            var kinds: [String] = []
            for kind in observed where known.contains(kind) && kinds.last != kind {
                kinds.append(kind)
            }
            if kinds.isEmpty { return [step.flatMap { known.contains($0) ? $0 : nil } ?? "answer"] }
            return Array(kinds.suffix(3))
        }

        static func activitySymbol(for kind: String) -> String {
            ContentState(phase: "answering", step: kind).symbol
        }

        static func activityLabel(for kind: String) -> String {
            switch kind {
            case "search": String(localized: "Search")
            case "list": String(localized: "Browse")
            case "read": String(localized: "Read")
            case "use": String(localized: "Tool")
            case "plan": String(localized: "Plan")
            case "run": String(localized: "Run")
            case "ask": String(localized: "Decide")
            case "write": String(localized: "Write")
            default: String(localized: "Think")
            }
        }

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
                case "answer": "ellipsis"
                default: "ellipsis"
                }
            case "answered": "checkmark.circle.fill"
            case "approval_waiting": "hand.raised.fill"
            case "input_requested": "questionmark.bubble.fill"
            case "failed": "exclamationmark.triangle.fill"
            case "stopped": "stop.circle.fill"
            default: "arrow.clockwise"
            }
        }

        /// Staleness takes precedence over the last state, even a ready result.
        func displaySymbol(isStale: Bool) -> String { isStale ? "arrow.clockwise" : symbol }

        func displayHeadline(isStale: Bool) -> String {
            isStale ? String(localized: "Open chat for an update") : headline
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
