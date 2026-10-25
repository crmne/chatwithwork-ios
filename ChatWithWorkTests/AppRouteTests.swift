import Foundation
import Testing
@testable import ChatWithWork

@Suite("Routes")
struct AppRouteTests {
    @Test("reads the organization from the first path segment")
    func accountSlug() {
        let route = AppRoute(path: "/482139075/chats/42")
        #expect(route.account?.rawValue == "482139075")
        #expect(route.path == "/chats/42")
        #expect(route.kind == .chat(number: 42))
    }

    @Test("needs seven digits or more to be an organization", arguments: ["123456", "12345a789", "chats"])
    func notAnAccount(segment: String) {
        #expect(AccountSlug(segment) == nil)
    }

    @Test("classifies the pages the shell cares about", arguments: [
        ("/chats", AppRoute.Kind.list(.chats)),
        ("/1000001/chats", .list(.chats)),
        ("/1000001/projects", .list(.projects)),
        ("/1000001/bots", .list(.bots)),
        ("/1000001/settings", .list(.settings)),
        ("/1000001/chats/new", .newChat),
        ("/1000001/chats/7", .chat(number: 7)),
        ("/users/sign_in", .authentication),
        ("/users/sign_up", .authentication),
        ("/users", .authentication),
        ("/users/password/edit", .authentication),
        ("/users/confirmation", .authentication),
        ("/users/auth/google_oauth2", .other),
        ("/recede_historical_location", .historicalLocation(.recede)),
        ("/1000001/refresh_historical_location", .historicalLocation(.refresh)),
        ("/resume_historical_location", .historicalLocation(.resume)),
        ("/rails/active_storage/blobs/redirect/abc/file.pdf", .file),
        ("/1000001/chats/7/edit", .other),
        ("/1000001/projects/3", .other),
        ("/", .other)
    ])
    func classifies(path: String, kind: AppRoute.Kind) {
        #expect(AppRoute(path: path).kind == kind)
    }

    @Test("knows the pages that become the shell's one chat screen")
    func chats() {
        #expect(AppRoute(path: "/1000001/chats/7").isChat)
        #expect(AppRoute(path: "/1000001/chats/new").isChat)
        #expect(!AppRoute(path: "/1000001/chats").isChat)
        #expect(!AppRoute(path: "/1000001/bots").isChat)
    }

    @Test("tells sign-in apart from the other account pages")
    func signIn() {
        #expect(AppRoute(path: "/users/sign_in").isSignIn)
        #expect(!AppRoute(path: "/users/sign_up").isSignIn)
        #expect(AppRoute(path: "/users/sign_up").isAuthentication)
    }

    @Test("starts inside the organization when it's known, at the new chat last used there")
    func startURLs() {
        let environment = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])
        let memory = SessionMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let acme = AccountSlug("482139075")!
        #expect(SidebarShell.startURL(environment: environment, account: nil, memory: memory).absoluteString == "https://chatwithwork.com/chats/new")
        #expect(SidebarShell.startURL(environment: environment, account: acme, memory: memory).absoluteString == "https://chatwithwork.com/482139075/chats/new")
        memory.setNewChatPath("/482139075/chats/new?project_id=3", in: acme)
        #expect(SidebarShell.startURL(environment: environment, account: acme, memory: memory).absoluteString == "https://chatwithwork.com/482139075/chats/new?project_id=3")
    }
}
