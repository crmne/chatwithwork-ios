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
}
