import Foundation
import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

/// The chat New chat, New bot or Decisions' All clear turns into in place
/// takes their screen where it stands (docs/server-contract.md, "New chat
/// and New bot").
@Suite("New chat's hand-off")
struct NewChatHandOffTests {
    private func url(_ path: String) -> URL { URL(string: "https://chatwithwork.com" + path)! }

    @Test("takes the chat a starting page's own form turned into", arguments: [
        "/1000001/chats/new", "/1000001/chats/new?project_id=3", "/1000001/bots/new", "/1000001/home", "/1000001/decisions"
    ])
    func takes(top: String) {
        #expect(NewChatHandOff.takes(url("/1000001/chats/42"), hasResponse: true, onTop: url(top), submittedFromTop: true))
    }

    @Test("leaves every other visit to the path configuration")
    func leaves() {
        let chat = url("/1000001/chats/42")
        let newChat = url("/1000001/chats/new")
        // A link, not a form's answer: the sidebar, a notification.
        #expect(!NewChatHandOff.takes(chat, hasResponse: false, onTop: newChat, submittedFromTop: true))
        // Another screen's form (a sheet's, or one that has gone).
        #expect(!NewChatHandOff.takes(chat, hasResponse: true, onTop: newChat, submittedFromTop: false))
        // A chat that says where from is a drill-down, pushed.
        #expect(!NewChatHandOff.takes(url("/1000001/chats/42?from=decisions"), hasResponse: true, onTop: url("/1000001/decisions"), submittedFromTop: true))
        // From a page that doesn't start chats.
        #expect(!NewChatHandOff.takes(chat, hasResponse: true, onTop: url("/1000001/chats/7"), submittedFromTop: true))
        #expect(!NewChatHandOff.takes(chat, hasResponse: true, onTop: url("/1000001/bots/7"), submittedFromTop: true))
        #expect(!NewChatHandOff.takes(chat, hasResponse: true, onTop: nil, submittedFromTop: true))
        // To anything but a chat.
        #expect(!NewChatHandOff.takes(url("/1000001/bots/7"), hasResponse: true, onTop: newChat, submittedFromTop: true))
        #expect(!NewChatHandOff.takes(newChat, hasResponse: true, onTop: newChat, submittedFromTop: true))
    }

    @Test("replaces the screen on top where it stands, at once, and says so")
    func replacing() {
        let response = VisitResponse(statusCode: 200, redirected: true, responseHTML: "<html></html>")
        let proposal = VisitProposal(url: url("/1000001/chats/42"), options: VisitOptions(action: .advance, response: response),
                                     properties: ["context": "default", "presentation": "replace_root", "skeleton": "chat"])
        #expect(!NewChatHandOff.isHandOff(proposal))

        let handOff = NewChatHandOff.replacing(proposal)
        #expect(NewChatHandOff.isHandOff(handOff))
        #expect(handOff.url == proposal.url)
        #expect(handOff.context == .default)
        #expect(handOff.presentation == .replace)
        #expect(!handOff.animated)
        #expect(handOff.options.action == .advance)
        #expect(handOff.options.response?.responseHTML == "<html></html>", "the form's response renders without a second request")
    }

    @MainActor
    @Test("shows what the screen it replaces showed, with no skeleton, until it lets go")
    func screen() throws {
        let leaving = UIViewController()
        leaving.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        leaving.navigationItem.title = "New chat"
        let window = UIWindow(frame: leaving.view.frame)
        window.rootViewController = leaving
        window.isHidden = false

        let controller = NewChatHandOff.screen(for: url("/1000001/chats/42"), replacing: leaving)
        #expect(controller.navigationItem.title == "New chat")
        #expect(PageSkeleton.current(on: controller) == nil, "no skeleton over a page already showing the question")
        #expect(NewChatHandOff.isHolding(controller))

        NewChatHandOff.dismiss(on: controller, animated: false)
        #expect(!NewChatHandOff.isHolding(controller))
        window.isHidden = true
    }
}
