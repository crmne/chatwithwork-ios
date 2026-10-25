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
    func inbox() {
        #expect(SharedInbox.take("../etc").isEmpty)
        #expect(SharedInbox.store([]) == nil)
    }
}
