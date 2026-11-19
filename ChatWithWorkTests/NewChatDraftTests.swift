import Testing
@testable import ChatWithWork

/// What's typed in New chat's sheet, kept while it's closed (path
/// configuration v3), per organization, until Send or signing out.
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
