import ActivityKit
import UIKit

/// Live Activities for answers that keep working while the person is
/// elsewhere: the organization, the step the answer is on ("Searching
/// Todoist") and how long, never the chat's title or anything from it.
/// ActivityKit starts activities only while the app is in front, and iOS
/// shows them only once the person leaves it, so the app starts one as soon
/// as a chat's composer says its answer works and registers the activity's
/// push token with the server (`POST /:account/chats/:number/live_activity`),
/// which pushes each step and ends it when the answer ends, saying how. The
/// app ends it itself when the composer says the answer is done while the
/// person is in the app; in the background it leaves the end to the
/// server's push, which keeps it on the Lock Screen saying how it ended.
///
/// An activity belongs to one run, the answer the composer names
/// (`LiveRun`), since Apple delivers a push only to the activity whose token
/// it is: the server decides which of them are current, and a chat's next run
/// replaces the last run's activity. A person dismissing a working card holds
/// for that run, and signing out ends everything, cancels every registration
/// and forgets those dismissals.
@MainActor
final class LiveActivities {
    static let shared = LiveActivities()

    #if DEBUG
        /// Synthetic system-surface previews, with no token or server registration.
        /// `-CWWLiveActivityPreview search|approval_waiting|answered|failed|stale`.
        /// Synthetic content for every state of Open Road. `*_bare` is what an
        /// end push carries today; `legacy` what an older server sends.
        static func previewState(_ scenario: String, now: Date) -> (state: ChatActivityAttributes.ContentState, age: TimeInterval) {
            let clock = Int64(now.timeIntervalSince1970)
            typealias State = ChatActivityAttributes.ContentState
            func state(_ phase: String, _ message: String?, step: String?, steps: Int?, age: Int64, service: String? = nil, services: [String]? = nil, trail: String? = nil, pace: String? = nil, agents: Int? = nil, waited: Int64? = nil) -> (State, TimeInterval) {
                (State(phase: phase, message: message, step: step, steps: steps, run: "preview", revision: 1, startedAt: clock - age, waitingSince: waited.map { clock - $0 }, service: service, services: services, trail: trail, pace: pace, agents: agents, heardAt: clock), TimeInterval(age))
            }
            let deepTrail = "srslruprxlsrrslpurxsrlsurrslrplsruxsrlurslpsrrrr"
            switch scenario {
            case "starting": return state("answering", "Answering", step: "answer", steps: 0, age: 3)
            case "deep": return state("answering", "Reading 12 files in HubSpot", step: "read", steps: 47, age: 1334, service: "hubspot", services: ["slack", "google_drive", "linear", "todoist", "notion", "hubspot"], trail: deepTrail)
            case "paced": return state("answering", "Searching Drive", step: "search", steps: 12, age: 348, service: "google_drive", services: ["slack", "google_drive"], trail: "srlrxsurlrsr", pace: "112214211212")
            case "agents": return state("answering", "Running 3 agents", step: "use", steps: 18, age: 302, service: nil, services: ["slack"], trail: "srlrxsurlrsr", agents: 3)
            case "agents_five": return state("answering", "Running 5 agents", step: "use", steps: 18, age: 302, services: ["slack"], trail: "srlrxsurlrsr", agents: 5)
            case "writing": return state("answering", "Writing the answer", step: "write", steps: 23, age: 401, services: ["google_drive"], trail: "slrrsuxrslpsrw")
            case "decision": return state("approval_waiting", "A change is waiting for your approval in Slack.", step: "use", steps: 12, age: 400, service: "slack", services: ["google_drive", "slack"], trail: "srlrusrlr", pace: "112214211", waited: 134)
            case "input": return state("input_requested", "A question is waiting for your answer.", step: "ask", steps: 8, age: 200, service: "todoist", services: ["todoist"], trail: "srlrusrl", pace: "11221421", waited: 37)
            case "finished": return state("answered", "Your answer is ready.", step: nil, steps: 24, age: 418, services: ["slack", "google_drive", "todoist"], trail: "srlrxsurlrsrpslrusrlrw")
            case "failed": return state("failed", "The answer couldn't finish.", step: nil, steps: 9, age: 200, services: ["google_drive"], trail: "srlrusrlr")
            case "stopped": return state("stopped", "The answer stopped.", step: nil, steps: 9, age: 200, services: ["google_drive"], trail: "srlrusrlr")
            case "finished_bare": return state("answered", "Your answer is ready.", step: nil, steps: nil, age: 418)
            case "failed_bare": return state("failed", "The answer couldn't finish.", step: nil, steps: nil, age: 200)
            case "stopped_bare": return state("stopped", "The answer stopped.", step: nil, steps: nil, age: 200)
            case "quiet":
                var quiet = state("quiet", nil, step: nil, steps: 12, age: 900, services: ["slack"], trail: "srlrxsurlrsrpslr").0
                quiet.heardAt = clock - 720
                return (quiet, 900)
            case "mcp": return state("answering", "Searching an MCP server", step: "search", steps: 4, age: 61, service: "mcp", services: ["mcp"], trail: "srls")
            case "long": return state("answering", "Reading 3 files in Jira and Confluence", step: "read", steps: 123, age: 3703, service: "atlassian", services: ["slack", "atlassian"], trail: deepTrail)
            case "legacy": return (State(phase: "answering", message: "Searching Drive", step: "search", steps: 7), 97)
            default: return state("answering", "Searching Drive", step: "search", steps: 5, age: 48, service: "google_drive", services: ["slack", "google_drive"], trail: "srlsruxps")
            }
        }

        static func preview(_ scenario: String) {
            Task {
                for activity in Activity<ChatActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                let now = Date()
                let (state, age) = previewState(scenario.replacingOccurrences(of: "minimal_", with: ""), now: now)
                let organization = scenario == "long" ? "Northwind Studio International Operations" : "Northwind Studio"
                let attributes = ChatActivityAttributes(organization: organization, path: "/1000001/chats/99999", startedAt: now.addingTimeInterval(-age))
                let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(scenario == "stale" ? 10 : 3600))
                do {
                    let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                    if scenario.hasPrefix("minimal") {
                        let other = ChatActivityAttributes(organization: organization, path: "/1000001/chats/99998", startedAt: now.addingTimeInterval(-18))
                        _ = try Activity.request(attributes: other, content: ActivityContent(state: previewState("working", now: now).state, staleDate: now.addingTimeInterval(3600)), pushType: nil)
                    }
                    for await phase in activity.activityStateUpdates {
                        NSLog("Live Activity preview %@: %@", scenario, String(describing: phase))
                    }
                } catch {
                    NSLog("Live Activity preview failed: %@", String(describing: error))
                }
            }
        }
    #endif

    private let environment = AppEnvironment.current

    /// The organization's name, for the activity (the sidebar knows it).
    var organizationName: () -> String? = { SidebarShell.current?.store.data?.organization.name }

    /// Whether the person is in the app, where a finished answer shows itself.
    var isInFront: () -> Bool = { UIApplication.shared.applicationState == .active }

    /// Whether there's a session: a web view going away after sign-out may
    /// still say its composer works.
    var isSignedIn: () -> Bool = { true }

    private let dismissals = LiveRunDismissals()
    /// What's watching each activity, by its id: its push token and its state.
    private var watchers: [String: [Task<Void, Never>]] = [:]
    /// Activities this app ended, whose dismissal isn't the person's.
    private var endedByApp: Set<String> = []

    /// The composer on `chatURL` changed.
    func noteState(_ state: ComposerState, chatURL: URL?) {
        guard isSignedIn(), let chatURL, case .chat = AppRoute(url: chatURL).kind else { return }
        let path = chatURL.path(percentEncoded: false)
        if state.working {
            start(for: path, run: state.liveRun, csrfToken: state.csrfToken)
        } else if isInFront(), !state.waiting {
            // A wait keeps its activity: the answer goes on after it, and iOS
            // can't start another from the background.
            end(for: path)
        }
    }

    // MARK: Starting and ending

    /// Sign-out or an expired session removes every old account surface.
    /// Snapshot now so an asynchronous dismissal cannot end a later login's work.
    @discardableResult
    func endAll() -> Task<Void, Never> {
        let current = Set(Activity<ChatActivityAttributes>.activities.map(\.id))
        endedByApp.formUnion(current)
        watchers.values.joined().forEach { $0.cancel() }
        watchers.removeAll()
        dismissals.removeAll()
        return Task {
            for activity in Activity<ChatActivityAttributes>.activities where current.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func start(for path: String, run: LiveRun?, csrfToken: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let activities = Activity<ChatActivityAttributes>.activities.filter { $0.attributes.path == path }
        let existing = activities.map {
            LiveActivityStart.Existing(id: $0.id, run: $0.attributes.run, isLive: $0.activityState == .active || $0.activityState == .stale)
        }
        switch LiveActivityStart.choose(for: run, existing: existing, dismissed: run.map { dismissals.contains($0.id) } ?? false) {
        case .none:
            return
        case .keep(let id):
            if let activity = activities.first(where: { $0.id == id }) { watch(activity, run: run, csrfToken: csrfToken) }
        case .start(let replacing):
            for activity in activities where replacing.contains(activity.id) { end(activity) }
            request(for: path, run: run, csrfToken: csrfToken)
        }
    }

    private func request(for path: String, run: LiveRun?, csrfToken: String?) {
        let attributes = ChatActivityAttributes(organization: organizationName() ?? "Chat with Work", path: path, startedAt: run?.startedAt ?? Date(), run: run?.id)
        var state = ChatActivityAttributes.ContentState.answering
        state.run = run?.id
        state.revision = run?.revision
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 60))
        let activity: Activity<ChatActivityAttributes>
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
        } catch {
            let error = error as NSError
            NSLog("Live Activity didn't start: %@ %ld", error.domain, error.code)
            return
        }
        watch(activity, run: run, csrfToken: csrfToken)
    }

    /// Registers the activity's token, and notes how it leaves. Once per
    /// activity, also for one that outlived the app's last launch.
    private func watch(_ activity: Activity<ChatActivityAttributes>, run: LiveRun?, csrfToken: String?) {
        guard watchers[activity.id] == nil else { return }

        let id = activity.id
        let path = activity.attributes.path
        let tokens = Task { [weak self, environment] in
            for await token in activity.pushTokenUpdates {
                let hex = token.map { String(format: "%02x", $0) }.joined()
                let outcome = await Self.register(hex, for: path, run: run?.id, csrfToken: csrfToken, environment: environment)
                if outcome == .runOver {
                    self?.end(activity)
                    return
                }
            }
        }
        let states = Task { [weak self] in
            var previous = activity.activityState
            for await state in activity.activityStateUpdates {
                self?.note(state, from: previous, id: id, run: activity.attributes.run)
                previous = state
            }
        }
        watchers[id] = [tokens, states]
    }

    private func note(_ state: ActivityState, from previous: ActivityState, id: String, run: String?) {
        if let run, LiveActivityEnding.isPersonsDismissal(from: previous, to: state, endedByApp: endedByApp.contains(id)) {
            dismissals.insert(run)
        }
        if state == .dismissed {
            watchers.removeValue(forKey: id)?.forEach { $0.cancel() }
            endedByApp.remove(id)
        }
    }

    private func end(for path: String) {
        for activity in Activity<ChatActivityAttributes>.activities where activity.attributes.path == path {
            end(activity)
        }
    }

    private func end(_ activity: Activity<ChatActivityAttributes>) {
        endedByApp.insert(activity.id)
        let id = activity.id
        Task {
            for activity in Activity<ChatActivityAttributes>.activities where activity.id == id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Tells the server the activity's push token, so it can end it.
    private static func register(_ token: String, for path: String, run: String?, csrfToken: String?, environment: AppEnvironment) async -> LiveActivityRegistration.Outcome {
        let route = AppRoute(path: path)
        guard let account = route.account, case .chat(let number) = route.kind else { return .gaveUp }

        var request = URLRequest(url: environment.url(path: "/\(account.rawValue)/chats/\(number)/live_activity"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let csrfToken { request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token") }
        var activity = ["token": token, "app_id": environment.bundleIdentifier, "environment": environment.pushEnvironment.apnsName]
        activity["run"] = run
        let body: [String: Any] = ["live_activity": activity]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        await WebSession.authorize(&request)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        // Without the token the server can't end the activity once the app is in the
        // background, so a failed request (offline, a server error) is tried again, waiting
        // longer each time.
        return await LiveActivityRegistration.attempt(
            send: { [request] in
                guard let (_, response) = try? await session.data(for: request) else { return nil }
                return (response as? HTTPURLResponse)?.statusCode
            },
            pause: { attempt in try? await Task.sleep(for: .seconds(2 << attempt)) }
        )
    }
}
