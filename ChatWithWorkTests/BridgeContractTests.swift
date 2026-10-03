import Foundation
import HotwireNative
import Testing
import UserNotifications
@testable import ChatWithWork

/// The messages each bridge component accepts, as the web sends them
/// (docs/server-contract.md). The JavaScript bridge adds `metadata` to every
/// message's data, so every payload here carries it too.
@Suite("Bridge contract")
struct BridgeContractTests {
    private func message(_ component: String, _ event: String, _ json: String) -> Message {
        Message(
            id: "1",
            component: component,
            event: event,
            metadata: .init(url: "https://chatwithwork.com/1000001/chats/42"),
            jsonData: json
        )
    }

    private let metadata = #""metadata":{"url":"https://chatwithwork.com/1000001/chats/42"}"#

    @Test("registers every component under its contract name")
    func names() {
        let names = BridgeRegistry.all.map { $0.name }
        #expect(names == [
            "alert", "review-prompt", "theme",
            "button", "menu", "search", "form", "share", "toast", "haptic",
            "context-menu", "auth-session", "notification-token"
        ])
        #expect(Set(names).count == names.count)
    }

    @Test("button reads Joe Masilotti's payload")
    func button() {
        let data: ButtonData? = message("button", "right", #"{"title":"New chat","iosImage":"square.and.pencil","androidImage":"edit_square","color":null,\#(metadata)}"#).data()
        #expect(data == ButtonData(title: "New chat", iosImage: "square.and.pencil", color: nil))
    }

    @Test("menu reads items, and the iOS extras when present")
    func menu() {
        let plain: MenuData? = message("menu", "connect", #"{"items":[{"title":"Pin","iosImage":"pin","destructive":false},{"title":"Delete","destructive":true}],\#(metadata)}"#).data()
        #expect(plain?.items.count == 2)
        #expect(plain?.items[1].destructive == true)
        #expect(plain?.side == nil)

        let switcher: MenuData? = message("menu", "connect", #"{"items":[{"title":"Acme","checked":true},{"title":"Initech"}],"side":"left","label":"Acme","header":"Organizations",\#(metadata)}"#).data()
        #expect(switcher?.side == "left")
        #expect(switcher?.label == "Acme")
        #expect(switcher?.isChooser == true)
        #expect(plain?.isChooser == false)
        #expect(switcher?.header == "Organizations")
        #expect(switcher?.items[0].checked == true)
    }

    @Test("menu selections reply with the item's index")
    func menuReply() throws {
        let reply = message("menu", "connect", "{}").replacing(data: MenuSelection(index: 2))
        let decoded = try JSONDecoder().decode(MenuSelection.self, from: Data(reply.jsonData.utf8))
        #expect(decoded.index == 2)
        #expect(reply.id == "1")
        #expect(reply.event == "connect")
    }

    @Test("form reads its button title")
    func form() {
        let data: FormData? = message("form", "connect", #"{"title":"Create project",\#(metadata)}"#).data()
        #expect(data == FormData(title: "Create project", color: nil))
    }

    @Test("share takes a link, a title and text, all optional")
    func share() {
        let full: ShareData? = message("share", "share", #"{"url":"https://chatwithwork.com/shared/abc","title":"Q3 planning","text":"Have a look",\#(metadata)}"#).data()
        #expect(full?.url == "https://chatwithwork.com/shared/abc")
        #expect(full?.title == "Q3 planning")

        let empty: ShareData? = message("share", "connect", "{\(metadata)}").data()
        #expect(empty == ShareData(url: nil, title: nil, text: nil, color: nil))
    }

    @Test("toast maps Rails flash kinds to styles")
    func toast() {
        let data: ToastData? = message("toast", "show", #"{"message":"Chat deleted.","type":"notice",\#(metadata)}"#).data()
        #expect(data?.message == "Chat deleted.")
        #expect(ToastStyle(type: "notice") == .notice)
        #expect(ToastStyle(type: "alert") == .alert)
        #expect(ToastStyle(type: "error") == .error)
        #expect(ToastStyle(type: nil) == .notice)
        #expect(ToastCenter.duration(for: "Saved.") == 2.5)
        #expect(ToastCenter.duration(for: String(repeating: "a", count: 300)) == 6)
    }

    @Test("haptic knows Joe's three kinds and the impact styles")
    func haptic() {
        let data: HapticData? = message("haptic", "vibrate", #"{"feedback":"light",\#(metadata)}"#).data()
        #expect(data?.feedback == "light")
        for name in ["success", "warning", "error", "selection", "light", "medium", "heavy", "soft", "rigid"] {
            #expect(Haptics.Feedback(rawValue: name) != nil)
        }
    }

    @Test("search takes a placeholder and answers with the query")
    func search() throws {
        let data: SearchData? = message("search", "connect", #"{"placeholder":"Search your chats",\#(metadata)}"#).data()
        #expect(data?.placeholder == "Search your chats")
        let reply = message("search", "connect", "{}").replacing(data: SearchQuery(query: "acme"))
        #expect(reply.jsonData.contains(#""query":"acme""#))
    }

    @Test("context menu items can carry text the app copies itself")
    func contextMenuCopy() throws {
        let json = #"{"items":[{"title":"Copy","copy":"The answer"},{"title":"Retry","destructive":false}],"rect":{"x":0,"y":0,"width":10,"height":10},\#(metadata)}"#
        let data: ContextMenuData = try #require(message("context-menu", "show", json).data())
        #expect(data.items[0].copy == "The answer")
        #expect(data.items[1].copy == nil)
        #expect(data.items[0].copyHtml == nil)
        #expect(data.items[0].pasteboardItem?["public.utf8-plain-text"] as? String == "The answer")
        #expect(data.items[0].pasteboardItem?["public.html"] == nil)
        #expect(data.items[1].pasteboardItem == nil)
    }

    @Test("context menu copies an answer as HTML and text together")
    func contextMenuRichCopy() throws {
        let json = #"{"items":[{"title":"Copy","copy":"**Hi**","copyHtml":"<p><strong>Hi</strong></p>"}],"rect":{"x":0,"y":0,"width":10,"height":10},\#(metadata)}"#
        let data: ContextMenuData = try #require(message("context-menu", "show", json).data())
        let item = try #require(data.items[0].pasteboardItem)
        #expect(item["public.utf8-plain-text"] as? String == "**Hi**")
        #expect(item["public.html"] as? String == "<p><strong>Hi</strong></p>")
        #expect(data.scroll == nil)
    }

    @Test("context menu places its anchor in web view coordinates")
    func contextMenu() throws {
        let json = #"{"items":[{"title":"Copy","iosImage":"doc.on.doc"}],"rect":{"x":300,"y":40,"width":32,"height":32},"scroll":{"x":0,"y":500},\#(metadata)}"#
        let data: ContextMenuData = try #require(message("context-menu", "show", json).data())
        #expect(data.items.first?.title == "Copy")

        // At the top of a page that starts under a 100pt bar, scrolled 500px.
        let frame = data.frame(zoom: 1, contentOffset: CGPoint(x: 0, y: 400))
        #expect(frame == CGRect(x: 300, y: 140, width: 32, height: 32))

        let zoomed = data.frame(zoom: 2, contentOffset: CGPoint(x: 0, y: 800))
        #expect(zoomed == CGRect(x: 600, y: 280, width: 64, height: 64))
    }

    @Test("auth sessions only start on the app's own server")
    func authSession() {
        let production = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com", "CWWEnvironment": "production"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])

        let relative = AuthSessionRequest(url: "/native/sign_ins/google_oauth2?challenge=abc", ephemeral: nil)
        #expect(relative.resolvedURL(in: production)?.absoluteString == "https://chatwithwork.com/native/sign_ins/google_oauth2?challenge=abc")
        #expect(AuthSessionRequest(url: "https://accounts.google.com/o/oauth2/auth", ephemeral: nil).resolvedURL(in: production) == nil)
        #expect(AuthSessionRequest(url: "http://chatwithwork.com/native/handoffs/abc", ephemeral: nil).resolvedURL(in: production) == nil)

        #expect(AuthSessionOutcome.success(URL(string: "chatwithwork://handoffs/complete")!).reply == AuthSessionReply(url: "chatwithwork://handoffs/complete", error: nil))
        #expect(AuthSessionOutcome(callbackURL: nil, error: nil).reply == AuthSessionReply(url: nil, error: "failed"))
    }

    @Test("notifications only open pages on the app's own server")
    func notificationRoute() {
        let environment = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])
        #expect(NotificationRoute.url(path: "/482139075/chats/42", environment: environment)?.absoluteString == "https://chatwithwork.com/482139075/chats/42")
        #expect(NotificationRoute.url(path: "//evil.example/chats", environment: environment) == nil)
        #expect(NotificationRoute.url(path: "https://evil.example", environment: environment) == nil)
        #expect(NotificationRoute.url(path: nil, environment: environment) == nil)
    }

    @Test("push state uses the contract's names")
    func pushState() throws {
        let state = PushState(status: "authorized", token: "abc", platform: "ios", environment: "sandbox", appId: "com.chatwithwork.app.debug")
        let json = try #require(String(data: JSONEncoder().encode(state), encoding: .utf8))
        #expect(json.contains(#""appId":"com.chatwithwork.app.debug""#))
        #expect(UNAuthorizationStatusNames.all == ["authorized", "provisional", "ephemeral", "denied", "not_determined"])
    }
}

private enum UNAuthorizationStatusNames {
    static var all: [String] {
        [UNAuthorizationStatus.authorized, .provisional, .ephemeral, .denied, .notDetermined].map(\.contractName)
    }
}
