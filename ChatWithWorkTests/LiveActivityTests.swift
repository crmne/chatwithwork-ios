import ActivityKit
import Foundation
import Testing
@testable import ChatWithWork

/// What the widget extension, Live Activities and the share extension share
/// with the app: its own links, the end push's content state, and the
/// shared files' inbox.
@Suite("Live Activities and app links")
struct LiveActivityTests {
    @Test func elapsedTimeOnlyAppearsForCurrentWork() {
        #expect(ChatActivityAttributes.ContentState.answering.showsElapsed(isStale: false))
        #expect(!ChatActivityAttributes.ContentState.answering.showsElapsed(isStale: true))
        for phase in ["answered", "approval_waiting", "input_requested", "failed", "stopped", "future_state"] {
            #expect(!ChatActivityAttributes.ContentState(phase: phase).showsElapsed(isStale: false))
            #expect(!ChatActivityAttributes.ContentState(phase: phase).showsElapsed(isStale: true))
        }
    }

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
        #expect(stopped.symbol == "stop.circle.fill")
    }

    @Test("decodes the server's step updates, which name the step and count them")
    func stepUpdates() throws {
        let state = try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"answering","message":"Searching Todoist","step":"search","steps":3}"#.utf8))
        #expect(state.isWorking)
        #expect(state.line == "Searching Todoist")
        #expect(state.symbol == "magnifyingglass")
        #expect(state.stepsLine == "3 steps so far")

        let first = ChatActivityAttributes.ContentState(phase: "answering", message: "Writing the answer", step: "write", steps: 1)
        #expect(first.stepsLine == "1 step so far")
        #expect(ChatActivityAttributes.ContentState.answering.stepsLine == nil)
        #expect(ChatActivityAttributes.ContentState.answering.line == "Answering")
        #expect(ChatActivityAttributes.ContentState(phase: "answering", step: "something new").symbol == "ellipsis")
    }

    @Test("recent activity decodes observed kinds and preserves older payloads")
    func recentActivity() throws {
        let state = try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"answering","step":"run","steps":3,"recent_steps":["search","read","run"]}"#.utf8))
        #expect(state.recentActivityKinds == ["search", "read", "run"])
        let legacy = try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"answering","step":"write"}"#.utf8))
        #expect(legacy.recentSteps == nil)
        #expect(legacy.recentActivityKinds == ["write"])
        #expect(ChatActivityAttributes.ContentState.answering.recentActivityKinds == ["answer"])
        let defensive = ChatActivityAttributes.ContentState(phase: "answering", step: "run", recentSteps: ["unknown", "plan", "search", "search", "read", "run"])
        #expect(defensive.recentActivityKinds == ["search", "read", "run"])
        #expect(ChatActivityAttributes.ContentState(phase: "answering", step: "run", recentSteps: ["search", "unknown"]).recentActivityKinds == ["search", "run"])
        #expect(ChatActivityAttributes.ContentState(phase: "answering", step: "read", recentSteps: ["unknown"]).recentActivityKinds == ["read"])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        #expect(encoded?["recent_steps"] as? [String] == ["search", "read", "run"])
        #expect(encoded?["recentSteps"] == nil)
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

    @Test("finished and waiting states have short headlines and safe navigation actions")
    func presentation() {
        let approval = ChatActivityAttributes.ContentState(phase: "approval_waiting")
        #expect(approval.headline == "Approval needed")
        #expect(approval.action == "Review change")
        #expect(approval.needsAttention)
        #expect(!approval.isWorking)
        let answered = ChatActivityAttributes.ContentState(phase: "answered")
        #expect(answered.headline == "Answer ready")
        #expect(answered.action == "Read answer")
        #expect(!answered.isWorking)
        let unknown = ChatActivityAttributes.ContentState(phase: "future_state")
        #expect(unknown.headline == "Open chat for an update")
        #expect(unknown.action == "Open chat")
        #expect(ChatActivityAttributes.ContentState(phase: "answering", steps: -1).stepsLine == nil)
    }

    @Test("missing content-free messages retain the actual kind of work")
    func missingMessages() {
        let expected = ["search": "Searching", "run": "Running a task", "read": "Reading", "write": "Writing the answer", "answer": "Answering", "ask": "Asking you to decide"]
        for (step, headline) in expected {
            let state = ChatActivityAttributes.ContentState(phase: "answering", message: "  ", step: step)
            #expect(state.headline == headline)
        }
        let answering = ChatActivityAttributes.ContentState(phase: "answering", step: "answer")
        #expect(answering.symbol == "ellipsis")
        #expect(answering.symbol != ChatActivityAttributes.ContentState(phase: "answering", step: "write").symbol)
        #expect(ChatActivityAttributes.ContentState(phase: "answering", message: "Running an agent", step: "run").headline == "Running an agent")
    }

    @Test("stale and unknown activity states never look successful or stopped")
    func stalePresentation() {
        for phase in ["answering", "answered", "approval_waiting", "failed", "stopped"] {
            let state = ChatActivityAttributes.ContentState(phase: phase)
            #expect(state.displaySymbol(isStale: true) == "arrow.clockwise")
            #expect(state.displayHeadline(isStale: true) == "Open chat for an update")
        }
        let unknown = ChatActivityAttributes.ContentState(phase: "future_state")
        #expect(unknown.symbol == "arrow.clockwise")
        #expect(unknown.line == "Open chat for an update")
        #expect(ChatActivityAttributes.ContentState(phase: "input_requested").symbol == "questionmark.bubble.fill")
        #expect(ChatActivityAttributes.ContentState(phase: "approval_waiting").symbol == "hand.raised.fill")
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
