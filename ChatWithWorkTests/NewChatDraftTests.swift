import UIKit
import Testing
@testable import ChatWithWork

/// What's typed in New chat, kept when it's left without sending (Back,
/// another place), per organization, until Send or signing out.
@MainActor
@Suite("New chat's draft", .serialized)
struct NewChatDraftTests {
    @Test("keeps words per organization, forgets blank ones, and clears on sign-out")
    func keeps() {
        NewChatDraft.clear()
        NewChatDraft.set("Plan the offsite", in: "482139075")
        NewChatDraft.set("Other work", in: "1000001")
        #expect(NewChatDraft.text(in: "482139075") == "Plan the offsite")
        #expect(NewChatDraft.text(in: "1000001") == "Other work")

        // Send clears the field, and with it the draft.
        NewChatDraft.set("", in: "482139075")
        #expect(NewChatDraft.text(in: "482139075") == nil)
        NewChatDraft.set("  \n", in: "1000001")
        #expect(NewChatDraft.text(in: "1000001") == nil)

        NewChatDraft.set("Before signing out", in: "482139075")
        NewChatDraft.clear()
        #expect(NewChatDraft.text(in: "482139075") == nil)
    }
}

/// A suggestion pressed on New chat or Decisions' All clear connects the
/// composer again with its words and `fill` (docs/server-contract.md, "The
/// composer"): they take the field's place, never joined to a draft.
@MainActor
@Suite("A suggestion's words", .serialized)
struct ComposerFillTests {
    private func state(_ json: String) throws -> ComposerState {
        try JSONDecoder().decode(ComposerState.self, from: Data(json.utf8))
    }

    @Test("replace what the field holds, the caret after them, with no draft joined")
    func fills() throws {
        NewChatDraft.clear()
        NewChatDraft.set("An old draft", in: "1000001")
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/1000001/chats/new")!)
        let composer = ComposerController.on(screen)
        composer.update(try state(#"{"placeholder":"Ask anything"}"#), connected: true)
        #expect(composer.view.textView.text == "An old draft", "a plain connect still brings the draft back")

        composer.update(try state(#"{"placeholder":"Ask anything","text":"Plan my week","fill":true}"#), connected: true)
        #expect(composer.view.textView.text == "Plan my week")
        #expect(composer.view.textView.selectedRange == NSRange(location: 12, length: 0))
        #expect(NewChatDraft.text(in: "1000001") == "Plan my week")
        ComposerController.focusesOnConnect = false
        NewChatDraft.clear()
    }

    @Test("reads fill only where it's sent")
    func decodes() throws {
        #expect(try state(#"{"placeholder":""}"#).fill == false)
        #expect(try state(#"{"placeholder":"","text":"Hi","fill":true}"#).fill)
    }
}
