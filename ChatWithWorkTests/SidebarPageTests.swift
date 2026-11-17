import Foundation
import Testing
@testable import ChatWithWork

/// The sidebar page the drawer shows where the server names one
/// (docs/server-contract.md, "The sidebar page").
@Suite("Sidebar page")
struct SidebarPageTests {
    let environment = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])
    var page: URL { environment.url(path: "/482139075/sidebar") }

    @Test("introduces itself as the app, but with no bridge components, so no bridge controller loads there")
    func userAgent() {
        let agent = SidebarPage.userAgent(prefix: environment.userAgentPrefix)
        #expect(agent.hasPrefix("Chat with Work; platform=ios; version="))
        #expect(!agent.contains("bridge-components"))
        #expect(!agent.contains("Hotwire Native"))
        #expect(!agent.contains("Turbo Native"))
    }

    @Test("follows the page a connect names, keeps the one loaded, and falls back to the native sidebar without one")
    func choice() throws {
        let named: SidebarPage.Connect = try decode(#"{"page":"/482139075/sidebar","belongsTo":"/482139075/bots/7","metadata":{"url":"https://chatwithwork.com/482139075/chats/9"}}"#)
        #expect(named.belongsTo == "/482139075/bots/7")
        #expect(SidebarPage.choose(named, loaded: nil) == .load("/482139075/sidebar"))
        #expect(SidebarPage.choose(named, loaded: "/482139075/sidebar") == .keep)
        #expect(SidebarPage.choose(named, loaded: "/731000042/sidebar") == .load("/482139075/sidebar"))

        let older: SidebarPage.Connect = try decode(#"{"metadata":{"url":"https://chatwithwork.com/482139075/chats/9"}}"#)
        #expect(SidebarPage.choose(older, loaded: "/482139075/sidebar") == .native)
        #expect(SidebarPage.choose(SidebarPage.Connect(page: "//evil.example/sidebar", belongsTo: nil), loaded: nil) == .native)
        #expect(SidebarPage.choose(SidebarPage.Connect(page: "https://evil.example/sidebar", belongsTo: nil), loaded: nil) == .native)
    }

    @Test("remembers the page per organization, for the next launch")
    func memory() {
        let memory = SessionMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let acme = AccountSlug("482139075")!
        #expect(memory.sidebarPagePath(in: acme) == nil)
        memory.setSidebarPagePath("/482139075/sidebar", in: acme)
        #expect(memory.sidebarPagePath(in: acme) == "/482139075/sidebar")
        #expect(memory.sidebarPagePath(in: AccountSlug("731000042")!) == nil)
        memory.setSidebarPagePath(nil, in: acme)
        #expect(memory.sidebarPagePath(in: acme) == nil)
    }

    @Test("lets only the page itself load there, and sends everything else where it belongs")
    func destinations() {
        let url = { (string: String) in URL(string: string)! }
        #expect(SidebarPage.destination(of: page, page: page, environment: environment) == .page)
        #expect(SidebarPage.destination(of: url("https://chatwithwork.com/482139075/sidebar?x=1"), page: page, environment: environment) == .page)
        #expect(SidebarPage.destination(of: url("https://chatwithwork.com/482139075/chats/9"), page: page, environment: environment) == .place(url("https://chatwithwork.com/482139075/chats/9")))
        #expect(SidebarPage.destination(of: url("https://chatwithwork.com/731000042/switch"), page: page, environment: environment) == .place(url("https://chatwithwork.com/731000042/switch")))
        #expect(SidebarPage.destination(of: url("https://chatwithwork.com/users/sign_in"), page: page, environment: environment) == .signedOut)
        #expect(SidebarPage.destination(of: url("https://support.chatwithwork.com/"), page: page, environment: environment) == .external(url("https://support.chatwithwork.com/")))
        #expect(SidebarPage.destination(of: url("about:blank"), page: page, environment: environment) == .ignore)
        #expect(SidebarPage.destination(of: url("javascript:alert(1)"), page: page, environment: environment) == .ignore)
        // Before any page is loaded, our own pages are places.
        #expect(SidebarPage.destination(of: page, page: nil, environment: environment) == .place(page))
    }

    @Test("reads what the page posts")
    func messages() {
        let base = environment.baseURL
        #expect(SidebarPage.Message(body: ["event": "ready"], base: base) == .ready)
        #expect(SidebarPage.Message(body: ["event": "close"], base: base) == .close)
        #expect(SidebarPage.Message(body: ["event": "visit", "url": "https://chatwithwork.com/482139075/decisions"], base: base) == .visit(URL(string: "https://chatwithwork.com/482139075/decisions")!))
        #expect(SidebarPage.Message(body: ["event": "visit", "url": "/482139075/chats/new"], base: base) == .visit(URL(string: "https://chatwithwork.com/482139075/chats/new")!))
        #expect(SidebarPage.Message(body: ["event": "confirm", "id": "3", "title": "Delete this chat?", "description": NSNull(), "confirm": "Delete", "dismiss": "Cancel", "destructive": true], base: base)
            == .confirm(.init(id: "3", title: "Delete this chat?", description: nil, confirm: "Delete", dismiss: "Cancel", destructive: true)))
        #expect(SidebarPage.Message(body: ["event": "confirm"], base: base) == nil)
        #expect(SidebarPage.Message(body: ["event": "dance"], base: base) == nil)
        #expect(SidebarPage.Message(body: "ready", base: base) == nil)
    }

    @Test("tells the page which page is on screen, quoting what it passes")
    func scripts() {
        #expect(SidebarPage.currentScript(url: URL(string: "https://chatwithwork.com/482139075/chats/9")!, belongsTo: nil)
            == #"window.chatWithWorkSidebar?.current("https:\/\/chatwithwork.com\/482139075\/chats\/9", null)"#)
        #expect(SidebarPage.currentScript(url: URL(string: "https://chatwithwork.com/1/chats/9")!, belongsTo: #"/1/bots/"7"#).hasSuffix(#"\/1\/bots\/\"7")"#))
        #expect(SidebarPage.answerScript(id: "3", confirmed: true) == #"window.chatWithWorkSidebar?.answer("3", true)"#)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
