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

    private func confirming() throws -> WebComposerState {
        try JSONDecoder().decode(WebComposerState.self, from: Data(#"{"acceptsFiles":true,"dictates":false,"confirmsAttach":true}"#.utf8))
    }

    private func sent(_ actions: [WebComposerAction]) throws -> (id: String, files: [ComposerFile]) {
        guard case .attach(let files, let id?) = try #require(actions.first) else {
            Issue.record("no attach with an id")
            return ("", [])
        }
        return (id, files)
    }

    @Test("a page that answers keeps the files in flight, and they leave only as it says, by reason")
    func confirmed() throws {
        reset()
        ComposerInbox.returnUnanswered()
        reset()
        let photo = ComposerFile(name: "photo.jpg", type: "image/jpeg", bytes: Data("p".utf8))
        let plan = ComposerFile(name: "plan.pdf", type: "application/pdf", bytes: Data("q".utf8))
        let other = ComposerFile(name: "other.txt", type: "text/plain", bytes: Data("o".utf8))
        ComposerInbox.files = [file, photo, plan, other, file]
        let (id, files) = try sent(ComposerInbox.take(for: try confirming(), at: newChat))
        #expect(files.count == 5)
        #expect(ComposerInbox.files.isEmpty)
        #expect(ComposerInbox.unanswered == 5)

        ComposerInbox.settle(id: id, results: [
            AttachedFile(name: "notes.txt", taken: true),
            AttachedFile(name: "photo.jpg", taken: false, reason: "locked"),
            AttachedFile(name: "plan.pdf", taken: false, reason: "refused"),
            AttachedFile(name: "other.txt", taken: false, reason: "removed"),
            AttachedFile(name: nil, taken: false, reason: "a later reason")
        ])
        #expect(ComposerInbox.unanswered == 0)
        #expect(ComposerInbox.files == [photo, file], "Kept: locked, and a reason not known yet")
        reset()
    }

    @Test("an older page, without confirmsAttach, is trusted with the files as before")
    func unconfirmed() throws {
        reset()
        ComposerInbox.files = [file]
        #expect(ComposerInbox.take(for: try state(), at: newChat) == [.attach(files: [file])])
        #expect(ComposerInbox.unanswered == 0)
    }

    @Test("a page gone, or quiet for ten minutes, gives its files back, and a late answer still takes out what it took")
    func unanswered() throws {
        reset()
        ComposerInbox.returnUnanswered()
        reset()
        let start = Date(timeIntervalSince1970: 0)
        ComposerInbox.files = [file]
        let old = try sent(ComposerInbox.take(for: try confirming(), at: newChat, now: start))
        let photo = ComposerFile(name: "photo.jpg", type: "image/jpeg", bytes: Data("p".utf8))
        ComposerInbox.files = [photo]
        let recent = try sent(ComposerInbox.take(for: try confirming(), at: newChat, now: start.addingTimeInterval(ComposerInbox.unansweredAfter)))

        ComposerInbox.returnUnanswered(olderThan: start.addingTimeInterval(ComposerInbox.unansweredAfter - 1))
        #expect(ComposerInbox.files == [file])
        #expect(ComposerInbox.unanswered == 1)
        ComposerInbox.settle(id: old.id, results: [AttachedFile(name: "notes.txt", taken: true)])
        #expect(ComposerInbox.files.isEmpty)

        ComposerInbox.returnUnanswered()
        #expect(ComposerInbox.files == [photo])
        ComposerInbox.settle(id: recent.id, results: [AttachedFile(name: "photo.jpg", taken: true)])
        #expect(ComposerInbox.files.isEmpty)
    }

    @Test("an attach the reply couldn't carry leaves flight and waits again")
    func replyFailed() throws {
        reset()
        ComposerInbox.files = [file]
        let actions = ComposerInbox.take(for: try confirming(), at: newChat)
        ComposerInbox.putBack(try #require(actions.first))
        #expect(ComposerInbox.unanswered == 0)
        #expect(ComposerInbox.files == [file])
        reset()
    }
}
