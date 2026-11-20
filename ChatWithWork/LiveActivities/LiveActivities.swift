import ActivityKit
import UIKit

/// Live Activities for answers that keep working while the person is
/// elsewhere: the chat's title (or a bot's name), the step the answer is on
/// ("Searching Todoist") and how long. No push carries the title: the app asks
/// the server for it with the web session (`GET .../live_activity`) as a
/// chat's composer first speaks, and starts the activity with it in its
/// attributes, which stay on the phone. The organization heads the card when
/// it couldn't ask.
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
        /// `-CWWLiveActivityMark chat` draws the logo a person's chat shows.
        /// `-CWWLiveActivityTitle "Q3 renewal plan"` heads it with a chat's title.
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
            case "agents", "agents_2", "agents_4", "agents_7", "agents_12":
                let count = Int(scenario.dropFirst("agents_".count)) ?? 3
                return state("answering", "Running \(count) agents", step: "use", steps: 18, age: 302, services: ["slack"], trail: "srlrxsurlrsr", pace: "112214211212", agents: count)
            case "writing": return state("answering", "Writing the answer", step: "write", steps: 23, age: 401, services: ["google_drive"], trail: "slrrsuxrslpsrw")
            case "decision": return state("approval_waiting", "A change is waiting for your approval in Slack.", step: "use", steps: 12, age: 400, service: "slack", services: ["google_drive", "slack"], trail: "srlrusrlr", pace: "112214211", waited: 134)
            case "decision_mcp": return state("approval_waiting", "A change is waiting for your approval.", step: "use", steps: 12, age: 400, service: "mcp", services: ["google_drive", "mcp"], trail: "srlrusrlr", pace: "112214211", waited: 134)
            case "decision_computer": return state("approval_waiting", "A change is waiting for your approval.", step: "run", steps: 12, age: 400, service: "computer", services: ["google_drive", "computer"], trail: "srlrusrlr", pace: "112214211", waited: 134)
            case "input": return state("input_requested", "A question is waiting for your answer.", step: "ask", steps: 8, age: 200, service: "todoist", services: ["todoist"], trail: "srlrusrl", pace: "11221421", waited: 37)
            case "input_plain": return state("input_requested", "A question is waiting for your answer.", step: "ask", steps: 8, age: 200, services: ["todoist"], trail: "srlrusrl", pace: "11221421", waited: 37)
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
                var (state, age) = previewState(scenario.replacingOccurrences(of: "minimal_", with: ""), now: now)
                state.mark = UserDefaults.standard.string(forKey: "CWWLiveActivityMark")
                let organization = scenario == "long" ? "Northwind Studio International Operations" : "Northwind Studio"
                let attributes = ChatActivityAttributes(organization: organization, path: "/1000001/chats/99999", startedAt: now.addingTimeInterval(-age), title: UserDefaults.standard.string(forKey: "CWWLiveActivityTitle"))
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
    /// Starts waiting for their titles, by path: the answer's run, and a mark
    /// for this start, so a second `working` for the same answer doesn't start
    /// another, and a new answer replaces the wait of one that ended.
    private var requesting: [String: (run: String?, start: UUID)] = [:]
    /// When a chat's title last failed to come (an older server answers 404),
    /// so it isn't asked again at every change of the composer.
    private var titleFailures: [String: Date] = [:]
    /// Chats whose composer last said its answer works, so one that finished while its title came starts nothing.
    private var working: Set<String> = []
    /// How to start each activity waiting for its title without it, should the app leave first.
    private var untitledStarts: [String: (start: UUID, run: () -> Void)] = [:]
    private var leavingObserver: NSObjectProtocol?

    /// The composer on `chatURL` changed, the app's own or the web's.
    func noteState(_ state: some LiveComposerState, chatURL: URL?) {
        guard isSignedIn(), let chatURL, case .chat = AppRoute(url: chatURL).kind else { return }
        let path = chatURL.path(percentEncoded: false)
        if state.working {
            working.insert(path)
            start(for: path, run: state.liveRun, mark: state.mark, csrfToken: state.csrfToken)
        } else if isInFront(), !state.waiting {
            // A wait keeps its activity: the answer goes on after it, and iOS
            // can't start another from the background.
            working.remove(path)
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
        requesting.removeAll()
        titleFailures.removeAll()
        untitledStarts.removeAll()
        working.removeAll()
        return Task {
            for activity in Activity<ChatActivityAttributes>.activities where current.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func start(for path: String, run: LiveRun?, mark: String?, csrfToken: String?) {
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
            request(for: path, run: run, mark: mark, csrfToken: csrfToken)
        }
    }

    /// Starts the activity once its title is known: at once when it was
    /// fetched already, otherwise after at most `titleWait`, since ActivityKit
    /// starts activities only while the app is in front.
    private func request(for path: String, run: LiveRun?, mark: String?, csrfToken: String?) {
        if let waiting = requesting[path], waiting.run == run?.id { return }
        let start = UUID()
        requesting[path] = (run?.id, start)
        // Someone who sends and leaves at once mustn't lose the activity to
        // the wait: ActivityKit refuses to start one from the background, so
        // leaving starts it there and then, without a title.
        untitledStarts[path] = (start, { [weak self] in self?.request(for: path, run: run, mark: mark, title: nil, csrfToken: csrfToken) })
        watchLeaving()
        Task { [weak self] in
            guard let self else { return }
            let title = await self.title(for: path)
            // A newer answer's start, or leaving the screen, took this one's place.
            guard self.requesting[path]?.start == start else { return }
            self.requesting[path] = nil
            self.untitledStarts[path] = nil
            guard self.isSignedIn(), self.working.contains(path) else { return }
            self.request(for: path, run: run, mark: mark, title: title?.headline(newChat: String(localized: "New chat")), csrfToken: csrfToken)
        }
    }

    /// Activities waiting for their titles as the app leaves the screen start without them.
    private func startWaitingUntitled() {
        let waiting = untitledStarts
        untitledStarts.removeAll()
        for (path, pending) in waiting where requesting[path]?.start == pending.start {
            requesting[path] = nil
            if isSignedIn(), working.contains(path) { pending.run() }
        }
    }

    private func watchLeaving() {
        guard leavingObserver == nil else { return }
        leavingObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startWaitingUntitled() }
        }
    }

    private func request(for path: String, run: LiveRun?, mark: String?, title: String?, csrfToken: String?) {
        let attributes = ChatActivityAttributes(organization: organizationName() ?? "Chat with Work", path: path, startedAt: run?.startedAt ?? Date(), run: run?.id, title: title)
        var state = ChatActivityAttributes.ContentState.answering
        state.run = run?.id
        state.revision = run?.revision
        state.mark = mark
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

    // MARK: The chat's title

    /// How long starting an activity waits for a title not fetched yet.
    static let titleWait: Duration = .milliseconds(800)

    /// How long a failure to get a chat's title holds before the server is
    /// asked again, so an older server's 404 isn't asked at every start.
    static let titleRetry: TimeInterval = 30

    /// Asks the server for a chat's title (the network by default; tests stand in).
    var fetchTitle: (String) async -> LiveActivityTitle? = { path in await LiveActivities.fetchTitle(for: path, environment: AppEnvironment.current) }

    /// The chat's title as the server says it now, within `titleWait`; nil
    /// otherwise. Never one asked for before this start: the person may have
    /// turned off "Show the chat and its answer" since, and an activity's
    /// title can't be taken back once it started.
    func title(for path: String) async -> LiveActivityTitle? {
        if let failed = titleFailures[path], Date().timeIntervalSince(failed) < Self.titleRetry { return nil }
        // A fetch of its own, never one an earlier start began.
        let fetch = Task { [weak self] () -> LiveActivityTitle? in
            guard let self else { return nil }
            let title = await self.fetchTitle(path)
            self.titleFailures[path] = title == nil ? Date() : nil
            return title
        }
        return await Self.first(of: fetch, within: Self.titleWait)
    }

    /// `fetch`'s value if it comes within `wait`, else nil at once, without
    /// waiting for the fetch to finish.
    static func first(of fetch: Task<LiveActivityTitle?, Never>, within wait: Duration) async -> LiveActivityTitle? {
        let race = TitleRace()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task { race.finish(await fetch.value) }
            Task {
                try? await Task.sleep(for: wait)
                race.finish(nil)
            }
        }
    }

    /// Asks the server for the chat's title with the web session.
    private static func fetchTitle(for path: String, environment: AppEnvironment) async -> LiveActivityTitle? {
        let route = AppRoute(path: path)
        guard let account = route.account, case .chat(let number) = route.kind else { return nil }

        var request = URLRequest(url: environment.url(path: "/\(account.rawValue)/chats/\(number)/live_activity"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5
        await WebSession.authorize(&request)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(LiveActivityTitle.self, from: data)
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

/// What a chat's composer says that Live Activities follow: whether its
/// answer works or waits for the person, which answer, who's at work on it,
/// and the page's token for registering the activity. The app's composer
/// (`ComposerState`) and the web's (`WebComposerState`) both say it.
nonisolated protocol LiveComposerState {
    var working: Bool { get }
    var waiting: Bool { get }
    var liveRun: LiveRun? { get }
    var mark: String? { get }
    var csrfToken: String? { get }
}

/// The first of the title and the limit to arrive resumes the waiter; the
/// other is dropped. Not generic: Swift 6.3's optimizer crashed on a generic
/// one in Release builds.
@MainActor
private final class TitleRace {
    var continuation: CheckedContinuation<LiveActivityTitle?, Never>?

    func finish(_ value: LiveActivityTitle?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
