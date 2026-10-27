import Foundation
import HotwireNative
import Testing
@testable import ChatWithWork

/// The bundled path configuration, which the server's
/// /configurations/ios_v2.json replaces (an exact copy of it). Its rules are part of the server
/// contract, so both must keep these behaviors.
@Suite("Path configuration")
struct PathConfigurationTests {
    private let configuration: PathConfiguration = {
        let url = Bundle.main.url(forResource: "path-configuration", withExtension: "json")!
        return PathConfiguration(sources: [.file(url)])
    }()

    private func properties(_ path: String) -> PathProperties {
        configuration.properties(for: path)
    }

    @Test("is bundled with the app")
    func bundled() {
        #expect(Bundle.main.url(forResource: "path-configuration", withExtension: "json") != nil)
        #expect(configuration.rules.count > 3)
    }

    @Test("pushes ordinary pages with pull to refresh", arguments: ["/1000001/projects/3", "/accounts", "/1000001/bots/7"])
    func defaultPages(path: String) {
        #expect(properties(path).context == .default)
        #expect(properties(path).pullToRefreshEnabled)
    }

    @Test("presents sign-in pages as sheets", arguments: [
        "/users/sign_in", "/users/sign_up", "/users", "/users/password/new",
        "/users/password/edit?reset_password_token=abc", "/users/confirmation/new"
    ])
    func authentication(path: String) {
        #expect(properties(path).context == .modal)
        #expect(!properties(path).pullToRefreshEnabled)
    }

    @Test("presents new and edit forms as sheets", arguments: [
        "/1000001/projects/new", "/1000001/projects/3/edit", "/1000001/chats/42/edit",
        "/1000001/chats/42/project/edit", "/accounts/new", "/1000001/settings/mcp_servers/5/edit"
    ])
    func forms(path: String) {
        #expect(properties(path).context == .modal)
        #expect(!properties(path).pullToRefreshEnabled)
    }

    @Test("makes every chat, new or not, the one screen at the root", arguments: [
        "/1000001/chats/new", "/chats/new", "/1000001/chats/new?project_id=3", "/1000001/chats/42", "/1000001/chats/42?message=7"
    ])
    func chats(path: String) {
        #expect(properties(path).context == .default)
        #expect(properties(path).presentation == .replaceRoot)
        #expect(!properties(path).pullToRefreshEnabled)
    }

    @Test("pushes shared chats without pull to refresh")
    func sharedChat() {
        #expect(properties("/shared/abc").context == .default)
        #expect(properties("/shared/abc").presentation == .default)
        #expect(!properties("/shared/abc").pullToRefreshEnabled)
    }

    @Test("shows Settings as a sheet, its sections pushed inside it", arguments: ["/1000001/settings", "/1000001/settings?tab=connectors"])
    func settings(path: String) {
        #expect(properties(path).context == .modal)
        #expect(properties(path).modalDismissGestureEnabled)
    }

    @Test("pushes lists over the chat, with pull to refresh", arguments: ["/1000001/chats", "/1000001/projects", "/1000001/bots"])
    func lists(path: String) {
        #expect(properties(path).context == .default)
        #expect(properties(path).presentation == .default)
        #expect(properties(path).pullToRefreshEnabled)
    }

    @Test("opens a chat's files in their viewer, full screen over the chat", arguments: [
        "/1000001/chats/42/files/eyJfcmFpbHMiOnsiZGF0YSI6MTJ9fQ==--abc", "/1000001/chats/42/files/abc?poll=2"
    ])
    func fileViewer(path: String) {
        #expect(properties(path).context == .modal)
        #expect(properties(path).modalStyle == .full)
        #expect(!properties(path).pullToRefreshEnabled)
        #expect(properties(path).presentation == .default, "never the chat's own screen")
    }

    @Test("keeps Hotwire's historical locations")
    func historicalLocations() {
        #expect(properties("/recede_historical_location").presentation == .pop)
        #expect(properties("/refresh_historical_location").presentation == .refresh)
        #expect(properties("/resume_historical_location").presentation == Navigation.Presentation.none)
    }
}
