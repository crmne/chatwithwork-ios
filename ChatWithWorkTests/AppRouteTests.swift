import Foundation
import HotwireNative
import Testing
import UIKit
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

    @Test("starts on the organization's home when it's known, whatever New chat last opened")
    func startURLs() {
        let environment = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])
        let memory = SessionMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let acme = AccountSlug("482139075")!
        #expect(SidebarShell.startURL(environment: environment, account: nil, memory: memory).absoluteString == "https://chatwithwork.com/home")
        #expect(SidebarShell.startURL(environment: environment, account: acme, memory: memory).absoluteString == "https://chatwithwork.com/482139075/home")
        memory.setNewChatPath("/482139075/chats/new?project_id=3", in: acme)
        #expect(SidebarShell.startURL(environment: environment, account: acme, memory: memory).absoluteString == "https://chatwithwork.com/482139075/home")
    }

    @Test("shows a historical location's notice, else its alert, as a toast")
    func historicalNotices() {
        let url = { (string: String) in URL(string: "https://chatwithwork.com\(string)")! }
        let notice = AppShell.notice(in: url("/recede_historical_location?notice=Chat%20renamed."))
        #expect(notice?.message == "Chat renamed." && notice?.style == .notice)
        let alert = AppShell.notice(in: url("/refresh_historical_location?alert=That%20name%20is%20taken."))
        #expect(alert?.message == "That name is taken." && alert?.style == .alert)
        #expect(AppShell.notice(in: url("/resume_historical_location?notice=Saved.&alert=Ignored"))?.message == "Saved.")
        #expect(AppShell.notice(in: url("/recede_historical_location")) == nil)
        #expect(AppShell.notice(in: url("/recede_historical_location?notice=")) == nil)
    }

    @Test("a server without the home starts on the chat list, a place, never New chat's sheet")
    func startURLsWithoutHome() {
        let environment = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])
        let memory = SessionMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let acme = AccountSlug("482139075")!
        let home = { (path: String) in URL(string: "https://chatwithwork.com\(path)")! }
        let fallback = { (path: String, account: AccountSlug?) in
            SidebarShell.startURLWithoutHome(failed: home(path), environment: environment, account: account, memory: memory)?.absoluteString
        }
        #expect(fallback("/home", nil) == "https://chatwithwork.com/chats")
        #expect(fallback("/482139075/home", nil) == "https://chatwithwork.com/482139075/chats")
        memory.setNewChatPath("/482139075/chats/new?project_id=3", in: acme)
        #expect(fallback("/482139075/home", nil) == "https://chatwithwork.com/482139075/chats")
        #expect(fallback("/home", acme) == "https://chatwithwork.com/482139075/chats")
        #expect(fallback("/482139075/chats/9", acme) == nil)
        #expect(fallback("/482139075/decisions", acme) == nil)
    }

    @MainActor
    @Test("a server without the home leaves a sidebar opened meanwhile open")
    func startWithoutHomeKeepsTheSidebarOpen() {
        final class Delegate: NavigatorDelegate {}
        let delegate = Delegate()
        let environment = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])
        let memory = SessionMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let shell = SidebarShell(environment: environment, account: AccountSlug("482139075")!, navigatorDelegate: delegate, memory: memory)
        shell.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        shell.view.layoutIfNeeded()

        shell.setOpen(true, animated: false)
        #expect(shell.startWithoutHome(failed: URL(string: "https://chatwithwork.com/482139075/home")!))
        #expect(shell.isOpen, "The person opened it while the home loaded")
        #expect(!shell.startWithoutHome(failed: URL(string: "https://chatwithwork.com/482139075/chats/9")!))
        withExtendedLifetime(delegate) {}
    }

    @Test("New chat is the organization's with the sidebar page, the chosen list's without")
    func newChatPaths() {
        let acme = AccountSlug("482139075")!
        let project = "/482139075/chats/new?project_id=3"
        #expect(SidebarShell.newChatPath(usesSidebarPage: true, chosen: project, account: acme) == "/482139075/chats/new")
        #expect(SidebarShell.newChatPath(usesSidebarPage: false, chosen: project, account: acme) == project)
        #expect(SidebarShell.newChatPath(usesSidebarPage: false, chosen: nil, account: acme) == "/482139075/chats/new")
    }

    @Test("a link to New chat starts a rebuilt shell there, anything else on the home")
    func rebuiltShellStarts() {
        let url = { (path: String) in URL(string: "https://chatwithwork.com\(path)")! }
        #expect(AppShell.startsAt(url("/482139075/chats/new")) == url("/482139075/chats/new"))
        #expect(AppShell.startsAt(url("/482139075/chats/new?project_id=3")) == url("/482139075/chats/new?project_id=3"))
        #expect(AppShell.startsAt(url("/482139075/chats/9")) == nil)
        #expect(AppShell.startsAt(url("/482139075/decisions")) == nil)
    }
}
