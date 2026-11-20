import Foundation
import Testing
@testable import ChatWithWork

/// What a share or a widget leaves for the web composer: only New chat's
/// composer takes it, files when it takes files, Dictate when it dictates.
@MainActor
@Suite("Composer inbox", .serialized)
struct ComposerInboxTests {
    private let newChat = URL(string: "https://chatwithwork.com/482139075/chats/new")!
    private let chat = URL(string: "https://chatwithwork.com/482139075/chats/42")!
    private let file = ComposerFile(name: "notes.txt", type: "text/plain", bytes: Data("hi".utf8))

    private func state(acceptsFiles: Bool = true, dictates: Bool = true) throws -> WebComposerState {
        try JSONDecoder().decode(WebComposerState.self, from: Data(#"{"working":false,"waiting":false,"acceptsFiles":\#(acceptsFiles),"dictates":\#(dictates)}"#.utf8))
    }

    private func reset() {
        ComposerInbox.files = []
        ComposerInbox.dictates = false
        ComposerInbox.text = nil
    }

    @Test("New chat's composer takes the shared files and Dictate, once")
    func newChatTakes() throws {
        reset()
        ComposerInbox.files = [file]
        ComposerInbox.dictates = true
        #expect(ComposerInbox.take(for: try state(), at: newChat) == [.attach(files: [file]), .dictate])
        #expect(ComposerInbox.take(for: try state(), at: newChat).isEmpty, "Each is handed over once")
    }

    @Test("a chat's composer connecting again first takes nothing")
    func chatTakesNothing() throws {
        reset()
        ComposerInbox.files = [file]
        ComposerInbox.dictates = true
        #expect(ComposerInbox.take(for: try state(), at: chat).isEmpty)
        #expect(ComposerInbox.take(for: try state(), at: nil).isEmpty)
        #expect(ComposerInbox.files == [file])
        #expect(ComposerInbox.dictates)
        reset()
    }

    @Test("what a composer didn't take goes back for the next one, files ahead of newer ones")
    func putBack() throws {
        reset()
        let newer = ComposerFile(name: "b.txt", type: "text/plain", bytes: Data("b".utf8))
        ComposerInbox.files = [newer]
        ComposerInbox.putBack(.attach(files: [file]))
        ComposerInbox.putBack(.dictate)
        #expect(ComposerInbox.files == [file, newer])
        #expect(ComposerInbox.dictates)
        reset()
    }

    @Test("files wait for a composer that takes them; a Dictate that can't start is dropped")
    func locked() throws {
        reset()
        ComposerInbox.files = [file]
        ComposerInbox.dictates = true
        #expect(ComposerInbox.take(for: try state(acceptsFiles: false, dictates: false), at: newChat).isEmpty)
        #expect(ComposerInbox.files == [file], "Shared files aren't lost to a locked composer")
        #expect(!ComposerInbox.dictates, "A later New chat doesn't start listening out of the blue")
        #expect(ComposerInbox.take(for: try state(), at: newChat) == [.attach(files: [file])])
    }

    private func confirming(acceptsFiles: Bool = true) throws -> WebComposerState {
        try JSONDecoder().decode(WebComposerState.self, from: Data(#"{"acceptsFiles":\#(acceptsFiles),"dictates":false,"confirmsAttach":true}"#.utf8))
    }

    private func sent(_ actions: [WebComposerAction]) -> (id: String, files: [ComposerFile])? {
        guard case .attach(let files, let id?) = actions.first else { return nil }
        return (id, files)
    }

    private func emptied() {
        ComposerInbox.returnUnanswered()
        ComposerInbox.visitStarted()
        reset()
    }

    private let photo = ComposerFile(name: "photo.jpg", type: "image/jpeg", bytes: Data("p".utf8))
    private let plan = ComposerFile(name: "plan.pdf", type: "application/pdf", bytes: Data("q".utf8))

    @Test("each reason: gone, again on this page once it unlocks, or for the next New chat")
    func confirmed() throws {
        emptied()
        ComposerInbox.files = [file, photo, plan, file, photo, plan]
        let (id, files) = try #require(sent(ComposerInbox.take(for: try confirming(), at: newChat)))
        #expect(files.count == 6)
        #expect(ComposerInbox.files.isEmpty)
        #expect(ComposerInbox.unanswered == 6)

        ComposerInbox.settle(id: id, results: [
            AttachedFile(name: "notes.txt", taken: true),
            AttachedFile(name: "photo.jpg", taken: false, reason: "locked"),
            AttachedFile(name: "plan.pdf", taken: false, reason: "refused"),
            AttachedFile(name: "notes.txt", taken: false, reason: "failed"),
            AttachedFile(name: nil, taken: false, reason: "removed"),
            AttachedFile(name: "plan.pdf", taken: false, reason: "a later reason")
        ])
        #expect(ComposerInbox.unanswered == 0)
        #expect(ComposerInbox.files == [photo, file, plan])
        // A state saying it unlocked gets only the locked one; the rest wait for the next New chat.
        #expect(sent(ComposerInbox.take(for: try confirming(), at: newChat, connecting: false))?.files == [photo])
        #expect(sent(ComposerInbox.take(for: try confirming(), at: newChat))?.files == nil, "Not before another visit")
        // Another visit gives back the one still in flight too, and the next New chat gets all three.
        ComposerInbox.visitStarted()
        #expect(sent(ComposerInbox.take(for: try confirming(), at: newChat))?.files == [photo, file, plan])
        emptied()
    }

    @Test("an older page, without confirmsAttach, is trusted with the files as before, and shares join those waiting")
    func unconfirmed() throws {
        emptied()
        ComposerInbox.files = [file]
        ComposerInbox.share([photo])
        #expect(ComposerInbox.take(for: try state(), at: newChat) == [.attach(files: [file, photo])])
        #expect(ComposerInbox.unanswered == 0)
        #expect(ComposerInbox.files.isEmpty)
    }

    @Test("a late answer counts wherever the file is now, and the same bytes shared twice stay two")
    func lateAnswer() throws {
        emptied()
        let start = Date(timeIntervalSince1970: 0)
        ComposerInbox.files = [file, file]
        let first = try #require(sent(ComposerInbox.take(for: try confirming(), at: newChat, now: start)))
        // Ten minutes without a word: they wait for the next New chat, which takes them again.
        ComposerInbox.returnUnanswered(olderThan: start.addingTimeInterval(ComposerInbox.unansweredAfter))
        #expect(ComposerInbox.files == [file, file])
        ComposerInbox.visitStarted()
        let second = try #require(sent(ComposerInbox.take(for: try confirming(), at: newChat)))

        // The first page did take the first copy; the second page's upload of it then fails.
        ComposerInbox.settle(id: first.id, results: [AttachedFile(name: "notes.txt", taken: true), AttachedFile(name: "notes.txt", taken: false, reason: "unavailable")])
        #expect(ComposerInbox.unanswered == 1)
        ComposerInbox.settle(id: second.id, results: [AttachedFile(name: "notes.txt", taken: false, reason: "failed"), AttachedFile(name: "notes.txt", taken: false, reason: "failed")])
        #expect(ComposerInbox.files == [file], "Only the copy no page took comes back")
        emptied()
    }

    @Test("a file that failed before, then comes back locked, goes again on this page once it unlocks")
    func failedThenLocked() throws {
        emptied()
        ComposerInbox.files = [file]
        let first = try #require(sent(ComposerInbox.take(for: try confirming(), at: newChat)))
        ComposerInbox.settle(id: first.id, results: [AttachedFile(name: "notes.txt", taken: false, reason: "failed")])
        ComposerInbox.visitStarted()
        let second = try #require(sent(ComposerInbox.take(for: try confirming(), at: newChat)))
        ComposerInbox.settle(id: second.id, results: [AttachedFile(name: "notes.txt", taken: false, reason: "locked")])
        #expect(sent(ComposerInbox.take(for: try confirming(), at: newChat, connecting: false))?.files == [file])
        emptied()
    }

    @Test("an attach the reply couldn't carry waits again at once, never twice")
    func replyFailed() throws {
        emptied()
        ComposerInbox.files = [file]
        let actions = ComposerInbox.take(for: try confirming(), at: newChat)
        let action = try #require(actions.first)
        ComposerInbox.putBack(action)
        ComposerInbox.putBack(action)
        #expect(ComposerInbox.unanswered == 0)
        #expect(ComposerInbox.files == [file])
        emptied()
    }
}
