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
        #expect(stopped.symbol == "stop.circle.fill")
    }

    @Test("decodes the server's step updates, which name the step and count them")
    func stepUpdates() throws {
        let state = try JSONDecoder().decode(ChatActivityAttributes.ContentState.self, from: Data(#"{"phase":"answering","message":"Searching Todoist","step":"search","steps":3}"#.utf8))
        #expect(state.isWorking)
        #expect(state.line == "Searching Todoist")
        #expect(state.symbol == "magnifyingglass")
        #expect(state.stepsLine == "3 steps")

        let first = ChatActivityAttributes.ContentState(phase: "answering", message: "Writing the answer", step: "write", steps: 1)
        #expect(first.stepsLine == "1 step")
        #expect(ChatActivityAttributes.ContentState.answering.stepsLine == nil)
        #expect(ChatActivityAttributes.ContentState.answering.line == "Answering")
        #expect(ChatActivityAttributes.ContentState(phase: "answering", step: "something new").symbol == "ellipsis")
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
