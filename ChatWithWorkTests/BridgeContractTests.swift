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
    @Test("the composer overlay reports native dimensions in one coordinate space")
    func composerLayout() throws {
        let data = try JSONEncoder().encode(ComposerAction.layout(height: 136, width: 1024))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["action"] as? String == "layout")
        #expect(payload["width"] as? Double == 1024)
        #expect(payload["height"] as? Double == 136)
    }

    @Test("composer permission reply uses the web action without a local policy")
    func composerPermission() throws {
        let data = try JSONEncoder().encode(ComposerAction.permissionMode(value: "edits"))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(payload == ["action": "permissionMode", "value": "edits"])
    }

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
        // `composer` while the app draws the composer itself (BridgeRegistry.drawsComposer), `web-composer` otherwise.
        let composer = (BridgeRegistry.drawsComposer ? ["composer"] : ["web-composer"]) + ["decisions"]
        #expect(names == [
            "alert", "review-prompt", "theme",
            "button", "menu", "search", "form", "share", "toast", "haptic",
            "context-menu", "auth-session", "notification-token", "sidebar"
        ] + composer + ["file"])
        #expect(Set(names).count == names.count)
    }

    @Test("web-composer reads the web composer's state, and leaves what an older page doesn't send at its default")
    func webComposerState() throws {
        let working: WebComposerState? = message("web-composer", "connect", #"{"working":true,"waiting":false,"run":"answer-7","revision":3,"startedAt":1763600000,"mark":"chat","csrfToken":"token","acceptsFiles":true,"dictates":true,\#(metadata)}"#).data()
        let state = try #require(working)
        #expect(state.working)
        #expect(!state.waiting)
        #expect(state.liveRun == LiveRun(id: "answer-7", revision: 3, startedAt: 1_763_600_000))
        #expect(state.mark == "chat")
        #expect(state.csrfToken == "token")
        #expect(state.acceptsFiles)
        #expect(state.dictates)

        let quiet: WebComposerState? = message("web-composer", "state", #"{"working":false,"waiting":false,"run":null,"revision":null,"startedAt":null,"mark":null,"csrfToken":null,"acceptsFiles":false,"dictates":false,\#(metadata)}"#).data()
        #expect(quiet?.liveRun == nil)
        #expect(quiet?.acceptsFiles == false)

        let bare: WebComposerState? = message("web-composer", "connect", #"{\#(metadata)}"#).data()
        #expect(bare?.working == false)
        #expect(bare?.dictates == false, "Nothing is assumed of a page that doesn't say")
    }

    @Test("web-composer's replies hand over shared files and start dictation")
    func webComposerReplies() throws {
        let attach = try JSONEncoder().encode(WebComposerAction.attach(files: [ComposerFile(name: "notes.txt", type: "text/plain", bytes: Data("hi".utf8))]))
        let files = try #require(JSONSerialization.jsonObject(with: attach) as? [String: Any])
        #expect(files["action"] as? String == "attach")
        let file = try #require((files["files"] as? [[String: String]])?.first)
        #expect(file == ["name": "notes.txt", "type": "text/plain", "data": "aGk="])

        let dictate = try JSONEncoder().encode(WebComposerAction.dictate)
        #expect(try JSONSerialization.jsonObject(with: dictate) as? [String: String] == ["action": "dictate"])
    }

    @Test("decisions reads how many wait, whether this is Decisions, and where it is")
    func decisions() throws {
        let data = try #require(message("decisions", "connect", #"{"waiting":3,"here":false,"url":"https://chatwithwork.com/482139075/decisions",\#(metadata)}"#).data() as DecisionsData?)
        #expect(data.waiting == 3)
        #expect(!data.here)
        #expect(data.url == "https://chatwithwork.com/482139075/decisions")
        let count: DecisionsCount? = message("decisions", "count", #"{"waiting":12,\#(metadata)}"#).data()
        #expect(count?.waiting == 12)
        let here: DecisionsData? = message("decisions", "connect", #"{"waiting":0,"here":true,"url":"/482139075/decisions",\#(metadata)}"#).data()
        #expect(here?.here == true)
    }

    @Test("Decisions' badge shows the count up to nine, then 9+, and none at zero; VoiceOver hears how many wait")
    func decisionsBadge() {
        #expect(DecisionsButton.badge(for: 0) == nil)
        #expect(DecisionsButton.badge(for: 3) == "3")
        #expect(DecisionsButton.badge(for: 9) == "9")
        #expect(DecisionsButton.badge(for: 12) == "9+")
        #expect(DecisionsButton.accessibilityLabel(for: 3) == "Decisions, 3 waiting")
        #expect(DecisionsButton.accessibilityLabel(for: 0) == "Decisions")
    }

    @Test("button reads Joe Masilotti's payload")
    func button() {
        let data: ButtonData? = message("button", "right", #"{"title":"New chat","iosImage":"square.and.pencil","androidImage":"edit_square","color":null,\#(metadata)}"#).data()
        #expect(data == ButtonData(title: "New chat", iosImage: "square.and.pencil", color: nil, nativeAction: nil))

        let newChat: ButtonData? = message("button", "right", #"{"title":"New chat","iosImage":"square.and.pencil","nativeAction":"new-chat",\#(metadata)}"#).data()
        #expect(newChat?.nativeAction == ButtonData.newChat, "The shell leaves out the page's New chat by its nativeAction")
    }

    @Test("sidebar's connect names the sidebar page and what the page on screen belongs under, or nothing from an older server")
    func sidebarConnect() {
        let named: SidebarPage.Connect? = message("sidebar", "connect", #"{"page":"/482139075/sidebar","belongsTo":null,\#(metadata)}"#).data()
        #expect(named == SidebarPage.Connect(page: "/482139075/sidebar", belongsTo: nil))
        let older: SidebarPage.Connect? = message("sidebar", "connect", #"{\#(metadata)}"#).data()
        #expect(older?.pagePath == nil)
    }

    @Test("notification-token's offer names its moment")
    func notificationOffer() {
        let approval: OfferData? = message("notification-token", "offer", #"{"reason":"approval",\#(metadata)}"#).data()
        #expect(approval?.reason == .approval)
        let answer: OfferData? = message("notification-token", "offer", #"{"reason":"answer",\#(metadata)}"#).data()
        #expect(answer?.reason == .answer)
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

    @Test("file reads the files a viewer shares, the file first, then its PDF")
    func file() {
        let data: FileShareData? = message("file", "connect", #"{"files":[{"url":"https://chatwithwork.com/rails/active_storage/blobs/proxy/abc/deck.pptx?disposition=attachment","name":"deck.pptx","contentType":"application/vnd.openxmlformats-officedocument.presentationml.presentation","title":"PowerPoint"},{"url":"/rails/active_storage/blobs/proxy/def/deck.pdf","name":"deck.pdf","contentType":"application/pdf","title":"PDF"}],\#(metadata)}"#).data()
        #expect(data?.files.map(\.name) == ["deck.pptx", "deck.pdf"])
        #expect(data?.files.map(\.isPDF) == [false, true])
        #expect(data?.files.first?.title == "PowerPoint")

        let page = URL(string: "https://chatwithwork.com/1000001/chats/42/files/xyz")!
        #expect(data?.files[1].resolvedURL(relativeTo: page)?.absoluteString == "https://chatwithwork.com/rails/active_storage/blobs/proxy/def/deck.pdf")
        let script = ViewerFile(url: "javascript:alert(1)", name: "x", contentType: nil, title: nil)
        #expect(script.resolvedURL(relativeTo: page) == nil, "Only http(s) addresses download")

        let bare: FileShareData? = message("file", "connect", #"{"files":[{"url":"/a.csv","name":"a.csv"}],\#(metadata)}"#).data()
        #expect(bare?.files.first?.contentType == nil, "contentType and title are optional")
    }

    @Test("a shared file keeps its name, without folders")
    func sharedFileName() {
        #expect(SessionDownload.safeName("Q3 board/deck.pptx") == "Q3 board-deck.pptx")
        #expect(SessionDownload.safeName("..") == "file")
        #expect(SessionDownload.safeName("  ") == "file")
        #expect(SessionDownload.safeName("report.docx") == "report.docx")
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
        let state = PushState(status: "authorized", token: "abc", platform: "ios", environment: "sandbox", appId: "com.chatwithwork.app.debug", needsKey: true)
        let json = try #require(String(data: JSONEncoder().encode(state), encoding: .utf8))
        #expect(json.contains(#""appId":"com.chatwithwork.app.debug""#))
        #expect(json.contains(#""needsKey":true"#))
        #expect(UNAuthorizationStatusNames.all == ["authorized", "provisional", "ephemeral", "denied", "not_determined"])
    }

    @Test("notification-token's key hands over the phone's notification key and its token")
    func notificationKey() {
        let data: NotificationKeyData? = message("notification-token", "key", #"{"key":"eyJ--abc","token":"a1b2",\#(metadata)}"#).data()
        #expect(data == NotificationKeyData(key: "eyJ--abc", token: "a1b2"))
    }
}

private enum UNAuthorizationStatusNames {
    static var all: [String] {
        [UNAuthorizationStatus.authorized, .provisional, .ephemeral, .denied, .notDetermined].map(\.contractName)
    }
}
