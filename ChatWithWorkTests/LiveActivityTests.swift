import ActivityKit
import Foundation
import Testing
@testable import ChatWithWork

/// What the widget extension, Live Activities and the share extension share
/// with the app: its own links, the end push's content state, and the
/// shared files' inbox.
@Suite("Live Activities and app links")
struct LiveActivityTests {
    @Test("decodes the server's end push content state")
    func contentState() throws {
        let state = try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"approval_waiting","message":"A change is waiting for your approval in Slack."}"#.utf8))
        #expect(state.phase == "approval_waiting")
        #expect(!state.isWorking)
        #expect(state.line == "A change is waiting for your approval in Slack.")

        let bare = try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"failed"}"#.utf8))
        #expect(bare.message == nil)
        #expect(bare.line == "The answer couldn't finish.")
        #expect(ChatActivityAttributes.ContentState.answering.isWorking)

        let stopped = try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"stopped","message":"The answer stopped."}"#.utf8))
        #expect(!stopped.isWorking)
    }

    @Test("decodes the server's step updates, which name the step and count them")
    func stepUpdates() throws {
        let state = try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"answering","message":"Searching Todoist","step":"search","steps":3}"#.utf8))
        #expect(state.isWorking)
        #expect(state.line == "Searching Todoist")
        #expect(state.steps == 3)
        #expect(ChatActivityAttributes.ContentState.answering.line == "Answering")
    }

    @Test("a person's chat shows the logo, a bot's run and an older server the bot")
    func mark() throws {
        let decode = { (json: String) in try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"phase":"answering","mark":"chat"}"#).showsLogo)
        #expect(try !decode(#"{"phase":"answering","mark":"bot"}"#).showsLogo)
        #expect(try !decode(#"{"phase":"answering"}"#).showsLogo)
    }

    @Test("the mark's paths parse as logo.svg's shapes, in its own box")
    func logoPaths() {
        let box = LogoPaths.scribble.boundingBoxOfPath.offsetBy(dx: LogoPaths.offset.x, dy: LogoPaths.offset.y)
        #expect(box.minX > 0 && box.minY > 0)
        #expect(box.maxX < LogoPaths.size.width && box.maxY < LogoPaths.size.height)
        #expect(box.width > 100 && box.height > 100)
        let bubble = LogoPaths.bubble.boundingBoxOfPath.offsetBy(dx: LogoPaths.offset.x, dy: LogoPaths.offset.y)
        #expect(bubble.width > box.width && bubble.height > box.height)
        #expect(!LogoPaths.pen.isEmpty)
        // Outside in: the pen finishes at the W's top left, where the Rails app's script/logo_pen ends.
        #expect(abs(LogoPaths.pen.currentPoint.x - 52) < 2 && abs(LogoPaths.pen.currentPoint.y - 48) < 2)
    }

    @Test("the server's run fields decode, and older payloads and activities have none")
    func runFields() throws {
        let decoder = JSONDecoder()
        let state = try decoder.decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"answered","message":"Ready","run":"a1","revision":7,"started_at":1793039262,"waiting_since":1793039300,"service":"slack","services":["slack","mcp"],"trail":"srA","agents":2,"heard_at":1793039400}"#.utf8))
        #expect(state.run == "a1")
        #expect(state.revision == 7)
        #expect(state.startedAt == 1793039262)
        #expect(state.waitingSince == 1793039300)
        #expect(state.service == "slack")
        #expect(state.services == ["slack", "mcp"])
        #expect(state.trail == "srA")
        #expect(state.agents == 2)
        #expect(state.heardAt == 1793039400)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        #expect(encoded?["started_at"] != nil)
        #expect(encoded?["waiting_since"] != nil)
        #expect(encoded?["heard_at"] != nil)
        #expect(encoded?["startedAt"] == nil)

        let older = try decoder.decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"answered"}"#.utf8))
        #expect(older.run == nil && older.revision == nil && older.startedAt == nil)

        let attributes = ChatActivityAttributes(organization: "Northwind", path: "/1/chats/2", startedAt: .now)
        #expect(attributes.run == nil)
        let stored = try JSONEncoder().encode(attributes)
        #expect(try decoder.decode(ChatActivityAttributes.self, from: stored).run == nil)
    }

    @Test("a run names its server start; without an id there is none")
    func liveRun() {
        let run = LiveRun(id: "a1", revision: 7, startedAt: 2)
        #expect(run?.id == "a1")
        #expect(run?.revision == 7)
        #expect(run?.startedAt == Date(timeIntervalSince1970: 2))
        #expect(LiveRun(id: "a1", revision: nil, startedAt: nil)?.revision == 0)
        #expect(LiveRun(id: "a1", revision: nil, startedAt: nil)?.startedAt == nil)
        #expect(LiveRun(id: nil, revision: 7, startedAt: 1) == nil)
        #expect(LiveRun(id: "", revision: 7, startedAt: 1) == nil)
    }

    @Test("a chat's activities follow its run: kept, replaced by a later run, and gone once dismissed")
    func choosingAnActivity() {
        typealias Existing = LiveActivityStart.Existing
        let a = LiveRun(id: "a", revision: 1, startedAt: nil)
        let b = LiveRun(id: "b", revision: 1, startedAt: nil)
        let working = Existing(id: "1", run: "a", isLive: true)
        let ended = Existing(id: "1", run: "a", isLive: false)

        #expect(LiveActivityStart.choose(for: a, existing: [], dismissed: false) == .start(replacing: []))
        #expect(LiveActivityStart.choose(for: a, existing: [working], dismissed: false) == .keep(id: "1"))
        // Dismissed, then the composer reconnects while the same answer works.
        #expect(LiveActivityStart.choose(for: a, existing: [], dismissed: true) == .none)
        // A later run starts though the last one's card is still on the Lock Screen.
        #expect(LiveActivityStart.choose(for: b, existing: [ended], dismissed: false) == .start(replacing: ["1"]))
        #expect(LiveActivityStart.choose(for: b, existing: [working], dismissed: false) == .start(replacing: ["1"]))
        // An answer that resumed after a wait has only its ended card left.
        #expect(LiveActivityStart.choose(for: a, existing: [ended], dismissed: false) == .start(replacing: ["1"]))
        // Started before the server named runs.
        #expect(LiveActivityStart.choose(for: a, existing: [Existing(id: "1", run: nil, isLive: true)], dismissed: false) == .keep(id: "1"))
    }

    @Test("an older server's composer behaves as it always did")
    func choosingWithoutARun() {
        let any = LiveActivityStart.Existing(id: "1", run: nil, isLive: false)
        #expect(LiveActivityStart.choose(for: nil, existing: [], dismissed: false) == .start(replacing: []))
        #expect(LiveActivityStart.choose(for: nil, existing: [any], dismissed: false) == .none)
    }

    @Test("only the person clearing a working card counts as dismissing it")
    func dismissalKinds() {
        #expect(LiveActivityEnding.isPersonsDismissal(from: .active, to: .dismissed, endedByApp: false))
        #expect(LiveActivityEnding.isPersonsDismissal(from: .stale, to: .dismissed, endedByApp: false))
        // The app's own ending, and a finished card leaving the Lock Screen.
        #expect(!LiveActivityEnding.isPersonsDismissal(from: .active, to: .dismissed, endedByApp: true))
        #expect(!LiveActivityEnding.isPersonsDismissal(from: .ended, to: .dismissed, endedByApp: false))
        #expect(!LiveActivityEnding.isPersonsDismissal(from: .active, to: .ended, endedByApp: false))
    }

    @MainActor @Test("a dismissal holds for its run, across launches, until the session ends or it expires")
    func dismissals() throws {
        let suite = "live-run-dismissals-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let dismissals = LiveRunDismissals(defaults: defaults)
        let now = Date()

        dismissals.insert("a", now: now)
        #expect(dismissals.contains("a", now: now))
        #expect(!dismissals.contains("b", now: now))
        #expect(LiveRunDismissals(defaults: defaults).contains("a", now: now))
        #expect(!dismissals.contains("a", now: now.addingTimeInterval(LiveRunDismissals.lifetime)))

        // Another identity signs in after this one left.
        dismissals.removeAll()
        #expect(!LiveRunDismissals(defaults: defaults).contains("a", now: now))
    }

    @Test("a registration stops when it's refused, or the run is over, and retries otherwise")
    func registrationOutcomes() async {
        func run(_ statuses: [Int?]) async -> (LiveActivityRegistration.Outcome, Int) {
            var remaining = statuses
            var sent = 0
            let outcome = await LiveActivityRegistration.attempt(send: {
                sent += 1
                return remaining.removeFirst()
            }, pause: { _ in })
            return (outcome, sent)
        }
        #expect(await run([201]) == (.registered, 1))
        #expect(await run([422]) == (.registered, 1))
        #expect(await run([409]) == (.runOver, 1))
        #expect(await run([500, nil, 201]) == (.registered, 3))
        #expect(await run(Array(repeating: 503, count: LiveActivityRegistration.attempts)) == (.gaveUp, LiveActivityRegistration.attempts))
    }

    @Test("signing out during a retry stops it before it sends the old session again")
    func registrationCancelled() async {
        final class Sent: @unchecked Sendable { var count = 0 }
        let sent = Sent()
        let (paused, pausing) = AsyncStream<Void>.makeStream()
        let (resumed, resuming) = AsyncStream<Void>.makeStream()
        let task = Task {
            await LiveActivityRegistration.attempt(send: {
                sent.count += 1
                return nil
            }, pause: { _ in
                pausing.yield()
                for await _ in resumed { break }
            })
        }
        for await _ in paused { break }
        task.cancel()
        resuming.yield()

        #expect(await task.value == .gaveUp)
        #expect(sent.count == 1)
    }

    @Test("builds the app's own links")
    func links() {
        #expect(AppLink.newChat().absoluteString == "chatwithwork://new-chat")
        #expect(AppLink.newChat(dictate: true).absoluteString == "chatwithwork://new-chat?dictate=1")
        let shared = AppLink.newChat(title: "Plan", text: "Read this", url: "https://example.com/a?b=1")
        let items = URLComponents(url: shared, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "url" }?.value == "https://example.com/a?b=1")
        #expect(items.first { $0.name == "title" }?.value == "Plan")
        #expect(AppLink.open(path: "/482139075/chats/42").absoluteString == "chatwithwork://open?path=/482139075/chats/42")
    }

    @MainActor @Test("sign-out cleanup ends already-running system activities", .enabled(if: ProcessInfo.processInfo.environment["CWW_TEST_ACTIVITYKIT"] == "1"))
    func endAllActivities() async throws {
        let attributes = ChatActivityAttributes(organization: "Synthetic test", path: "/1000001/chats/99999", startedAt: .now)
        let activity = try Activity.request(attributes: attributes, content: ActivityContent(state: ChatActivityAttributes.ContentState.answering, staleDate: .now.addingTimeInterval(300)), pushType: nil)
        let registeredBy = Date().addingTimeInterval(5)
        while !Activity<ChatActivityAttributes>.activities.contains(where: { $0.id == activity.id }), Date() < registeredBy {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(Activity<ChatActivityAttributes>.activities.contains(where: { $0.id == activity.id }))
        await LiveActivities.shared.endAll().value
        let dismissedBy = Date().addingTimeInterval(5)
        while activity.activityState == .active, Date() < dismissedBy {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(activity.activityState == .ended || activity.activityState == .dismissed)
    }

    @Test("takes nothing for a folder that isn't a share's")
    func inbox() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(SharedInbox.take("../etc", in: root).isEmpty)

        let empty = try #require(SharedInbox.begin(in: root))
        #expect(SharedInbox.finish(empty, entries: []) == nil)
        #expect(!FileManager.default.fileExists(atPath: empty.folder.path))
    }

    @Test("hands over the shared files once, then forgets them")
    func inboxRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("plan.pdf")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("%PDF-1.7".utf8).write(to: source)

        let share = try #require(SharedInbox.begin(in: root))
        let entry = try #require(SharedInbox.keep(source, name: "plan.pdf", type: "application/pdf", index: 0, in: share))
        let name = try #require(SharedInbox.finish(share, entries: [entry]))

        #expect(SharedInbox.take(name, in: root) == [SharedFile(name: "plan.pdf", type: "application/pdf", data: Data("%PDF-1.7".utf8))])
        #expect(SharedInbox.take(name, in: root).isEmpty)
    }
}
