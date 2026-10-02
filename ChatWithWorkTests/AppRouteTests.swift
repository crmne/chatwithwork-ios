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
        ("/chats", AppRoute.Kind.tabRoot(.chats)),
        ("/1000001/chats", .tabRoot(.chats)),
        ("/1000001/projects", .tabRoot(.projects)),
        ("/1000001/settings", .tabRoot(.settings)),
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

    @Test("knows which tab a link belongs in")
    func preferredTab() {
        #expect(AppRoute(path: "/1000001/chats/7").preferredTab == .chats)
        #expect(AppRoute(path: "/1000001/projects/3").preferredTab == .projects)
        #expect(AppRoute(path: "/1000001/settings").preferredTab == .settings)
        #expect(AppRoute(path: "/1000001/join/abcd").preferredTab == nil)
    }

    @Test("tells sign-in apart from the other account pages")
    func signIn() {
        #expect(AppRoute(path: "/users/sign_in").isSignIn)
        #expect(!AppRoute(path: "/users/sign_up").isSignIn)
        #expect(AppRoute(path: "/users/sign_up").isAuthentication)
    }

    @Test("starts tabs inside the organization when it's known")
    func tabURLs() {
        let environment = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])
        #expect(AppTab.chats.url(in: environment, account: nil).absoluteString == "https://chatwithwork.com/chats")
        #expect(AppTab.projects.url(in: environment, account: AccountSlug("482139075")).absoluteString == "https://chatwithwork.com/482139075/projects")
        #expect(AppTab.newChat.isAction)
        #expect(AppTab.destinations == [.chats, .projects, .settings])
    }
}
