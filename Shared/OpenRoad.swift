import Foundation

/// What the Live Activity draws, worked out from what the server said: a bot on
/// a road it lays down as it works. Pure, so it can be tested without a Lock
/// Screen. Everything here is observed. The road has no end until there is one,
/// and nothing may become a percentage, an estimate, a planned stage or a
/// checkmark.
nonisolated struct OpenRoad: Equatable {
    enum Stage: Equatable {
        case starting, working, agents, writing, decision, input, finished, failed, stopped, stale
    }

    enum Face: String, Equatable {
        case open, closed, right, left, down, up, focus, wide, brow, happy, flat
    }

    enum Tool: String, Equatable {
        case search, read, list, use, plan, run, write, ask
    }

    /// One observed step, as tall as the time it took, where the server says.
    /// `refused` is one that failed or the person turned down.
    struct Tick: Equatable {
        var height: CGFloat
        var refused = false
    }

    enum Clock: Equatable {
        /// Counting up from a moment: the answer's start, or a wait's.
        case running(since: Date)
        /// How long it took, once it's over.
        case fixed(TimeInterval)
        case hidden
    }

    /// The trail is drawn compressed, with its origin scrolled off, from here.
    static let deepAfter = 24
    static let maxTicks = 48
    static let maxStops = 6
    /// Bots drawn side by side on a fork. Any more read as `+n`.
    static let maxAgentBots = 3
    /// `pace` digits: under 2 seconds, under 10, under 60, a minute or more.
    static let paceHeights: [Character: CGFloat] = ["1": 6, "2": 13, "3": 21, "4": 29]
    /// Where the time of each step isn't known, every tick is this tall.
    static let evenHeight: CGFloat = 14

    /// Built-in services' words in `message`, and which of them are drawn. Keep
    /// in step with `script/live-activity-assets`.
    static let serviceNames: [String: String] = [
        "google_drive": "Drive", "gmail": "Gmail", "google_calendar": "Calendar", "dropbox": "Dropbox",
        "onedrive": "OneDrive", "sharepoint": "SharePoint", "outlook": "Outlook", "teams": "Teams",
        "nextcloud": "Nextcloud", "odoo": "Odoo", "chatwoot": "Chatwoot", "slack": "Slack",
        "discord": "Discord", "sendfox": "SendFox", "tidycal": "TidyCal", "x": "X", "basecamp": "Basecamp",
        "notion": "Notion", "todoist": "Todoist", "github": "GitHub", "bugsink": "Bugsink", "linear": "Linear",
        "atlassian": "Jira and Confluence", "granola": "Granola", "fireflies": "Fireflies", "hubspot": "HubSpot",
        "salesforce": "Salesforce", "intercom": "Intercom", "asana": "Asana", "monday": "monday.com",
        "figma": "Figma", "lattice": "Lattice", "netsuite": "NetSuite", "chargebee": "Chargebee",
        "databricks": "Databricks", "looker": "Looker", "pidgeon": "Pidgeon"
    ]
    /// People's own servers and computers: a generic glyph, never a name.
    static let genericServices: Set<String> = ["mcp", "computer"]
    static let monochromeServices: Set<String> = ["basecamp", "discord", "github", "intercom", "pidgeon", "x", "mcp", "computer"]

    let stage: OpenRoad.Stage
    let face: Face
    let tool: Tool?
    let ticks: [Tick]
    let stops: [String]
    let service: String?
    let steps: Int
    let agents: Int?
    /// `trail` and `services` didn't come: an older server, or an end push.
    let isLegacy: Bool
    let clock: Clock
    /// The push this shows, for "Last heard". Nil on an older server.
    let heardAt: Date?
    /// The words, as sent where they came from the server.
    let message: String

    init(state: ChatActivityAttributes.ContentState, startedAt: Date, isStale: Bool, now: Date = .now) {
        let start = state.startedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? startedAt
        let heard = state.heardAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let waitingSince = state.waitingSince.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? start

        steps = max(state.steps ?? 0, 0)
        message = state.line
        heardAt = heard
        isLegacy = state.trail == nil
        ticks = Self.ticks(trail: state.trail, pace: state.pace, steps: steps)
        service = state.service
        stops = Self.stops(services: state.services, current: service)
        agents = (state.agents ?? 0) >= 2 ? state.agents : nil

        let working = state.isWorking
        let waiting = state.needsAttention
        // An ended state never shows stale. A wait stays true, so it stays amber.
        if isStale, working {
            stage = .stale
        } else if !working, !waiting, !["answered", "failed", "stopped"].contains(state.phase) {
            stage = .stale
        } else {
            switch state.phase {
            case "answered": stage = .finished
            case "failed": stage = .failed
            case "stopped": stage = .stopped
            case "approval_waiting": stage = .decision
            case "input_requested": stage = .input
            default:
                if agents != nil {
                    stage = .agents
                } else if state.step == "write" {
                    stage = .writing
                } else if steps == 0, state.step == nil || state.step == "answer" {
                    stage = .starting
                } else {
                    stage = .working
                }
            }
        }

        switch stage {
        case .starting: (face, tool) = (.open, nil)
        case .working, .writing: (face, tool) = Self.pose(for: state.step)
        case .agents: (face, tool) = (.focus, nil)
        case .decision: (face, tool) = (.wide, nil)
        case .input: (face, tool) = (.brow, nil)
        case .finished: (face, tool) = (.happy, nil)
        // Calm on purpose: a failure may be serious, and x eyes would joke about it.
        case .failed, .stale: (face, tool) = (.closed, nil)
        case .stopped: (face, tool) = (.flat, nil)
        }

        switch stage {
        case .starting, .working, .agents, .writing: clock = .running(since: start)
        case .decision, .input: clock = .running(since: waitingSince)
        case .finished, .stopped:
            // Only a heard end gives a total. Without one, none is inferred.
            if let heard, state.startedAt != nil { clock = .fixed(max(heard.timeIntervalSince(start), 0)) } else { clock = .hidden }
        case .failed, .stale: clock = .hidden
        }
    }

    static func pose(for step: String?) -> (Face, Tool?) {
        switch step {
        case "search": (.right, .search)
        case "list": (.left, .list)
        case "read": (.down, .read)
        case "use": (.focus, .use)
        case "plan": (.up, .plan)
        case "run": (.focus, .run)
        case "write": (.down, .write)
        case "ask": (.brow, .ask)
        default: (.up, nil)
        }
    }

    /// The height each step of a `count`-long trail took, or nil where `pace`
    /// doesn't say that of every one of them.
    static func heights(pace: String?, count: Int) -> [CGFloat]? {
        guard let pace, pace.count == count else { return nil }
        let heights = pace.compactMap { paceHeights[$0] }
        return heights.count == count ? heights : nil
    }

    /// The trail, or even ticks counted from `steps` where an older server
    /// sends none: the count is real, the heights would not be.
    static func ticks(trail: String?, pace: String? = nil, steps: Int) -> [Tick] {
        guard let trail else {
            return Array(repeating: Tick(height: evenHeight), count: min(steps, maxTicks))
        }
        let heights = heights(pace: pace, count: trail.count) ?? Array(repeating: evenHeight, count: trail.count)
        return zip(trail, heights).suffix(maxTicks).filter(\.0.isLetter).map { letter, height in
            Tick(height: height, refused: letter != Character(letter.lowercased()))
        }
    }

    /// Whether a logo ships for this key. A key this build doesn't know, a
    /// newer server's, draws as a neutral dot.
    static func hasLogo(_ key: String) -> Bool {
        serviceNames[key] != nil || genericServices.contains(key)
    }

    /// Stops behind the bot, oldest first, newest kept. The service it's in now
    /// is the headline's or the held card's, so it isn't a stop yet.
    static func stops(services: [String]?, current: String?) -> [String] {
        var seen = Set<String>()
        let drawn = (services ?? []).filter { seen.insert($0).inserted && $0 != current }
        return Array(drawn.suffix(maxStops - 1))
    }

    var isDeep: Bool { ticks.count >= Self.deepAfter }
    var isWaiting: Bool { stage == .decision || stage == .input }
    var isOver: Bool { stage == .finished || stage == .failed || stage == .stopped }
    var hasBand: Bool { isWaiting || stage == .failed }

    var serviceName: String? { service.flatMap { Self.serviceNames[$0] } }

    /// What `service`'s logo sits beside in the headline: "Searching" and
    /// "Drive" for "Searching Drive", "Reading 12 files" and "HubSpot" for
    /// "Reading 12 files in HubSpot". Nil when the words don't name it, as for
    /// an MCP server, whose glyph then follows the words as sent.
    var splitHeadline: (verb: String, name: String)? {
        guard let name = serviceName else { return nil }
        for suffix in [" in \(name)", " \(name)"] where message.hasSuffix(suffix) && message.count > suffix.count {
            return (String(message.dropLast(suffix.count)), name)
        }
        return nil
    }

    var headline: String {
        switch stage {
        case .starting: String(localized: "Starting")
        case .working, .agents, .writing: message
        case .decision: String(localized: "Approve a change")
        case .input: String(localized: "A question for you")
        case .finished: String(localized: "Answer ready")
        case .failed: String(localized: "Couldn't finish")
        case .stopped: String(localized: "Stopped")
        case .stale:
            heardAt.map { String(localized: "Last heard \(Self.time($0))") } ?? String(localized: "Open chat for an update")
        }
    }

    var bandAction: String {
        switch stage {
        case .decision: String(localized: "Review")
        case .input: String(localized: "Reply")
        default: String(localized: "Open")
        }
    }

    var stepsLabel: String? {
        guard steps > 0 else { return nil }
        return steps == 1 ? String(localized: "1 step") : String(localized: "\(steps) steps")
    }

    /// The small, untimed time `Last heard` and the Island's trailing show.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "6:58", "1:02:03".
    static func clockText(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        let (hours, minutes, rest) = (whole / 3600, whole / 60 % 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    private static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute, .second] : [.second]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: max(seconds, 1)) ?? ""
    }

    /// One label for the whole card: words always say what a face or colour
    /// shows, and bot and road stay hidden from VoiceOver.
    func accessibilityLabel(organization: String, now: Date = .now) -> String {
        let stepsPart = stepsLabel.map { " \($0)." } ?? ""
        var running = ""
        var since = ""
        if case .running(let date) = clock {
            let seconds = Self.spoken(now.timeIntervalSince(date))
            running = String(localized: " Running \(seconds).")
            since = seconds
        }
        switch stage {
        case .starting:
            return String(localized: "Chat with Work, \(organization). Starting.") + running
        case .working, .writing:
            return String(localized: "Chat with Work, \(organization). \(message).") + stepsPart + running
        case .agents:
            return "\(message)." + stepsPart + running
        case .decision:
            let waiting = String(localized: "Waiting \(since).")
            if let serviceName {
                return String(localized: "A change in \(serviceName) is waiting for your approval.") + " \(waiting) " + String(localized: "Double-tap to review.")
            }
            return String(localized: "A change is waiting for your approval.") + " \(waiting) " + String(localized: "Double-tap to review.")
        case .input:
            return String(localized: "A question is waiting for your answer.")
        case .finished:
            if case .fixed(let total) = clock {
                return String(localized: "Answer ready. Took \(Self.spoken(total)).") + stepsPart
            }
            return String(localized: "Answer ready.") + stepsPart
        case .failed:
            return String(localized: "The answer couldn't finish.")
        case .stopped:
            return String(localized: "Stopped.") + stepsPart
        case .stale:
            if let heardAt { return String(localized: "No update since \(Self.time(heardAt)). Open the chat to check.") }
            return String(localized: "Open chat for an update")
        }
    }
}
