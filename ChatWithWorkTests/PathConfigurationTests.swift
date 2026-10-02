import Foundation
import HotwireNative
import Testing
@testable import ChatWithWork

/// The bundled path configuration, which the server's
/// /configurations/ios_v1.json replaces. Its rules are part of the server
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

    @Test("pushes ordinary pages with pull to refresh", arguments: ["/1000001/projects/3", "/accounts", "/1000001/settings?tab=connectors"])
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

    @Test("opens new chat as a sheet, with or without a project", arguments: ["/1000001/chats/new", "/chats/new", "/1000001/chats/new?project_id=3"])
    func newChat(path: String) {
        #expect(properties(path).context == .modal)
        #expect(properties(path).modalDismissGestureEnabled)
        #expect(!properties(path).pullToRefreshEnabled)
    }

    @Test("keeps pull to refresh off on a conversation", arguments: ["/1000001/chats/42", "/1000001/chats/42?message=7", "/shared/abc"])
    func conversation(path: String) {
        #expect(properties(path).context == .default)
        #expect(!properties(path).pullToRefreshEnabled)
    }

    @Test("refreshes tab roots", arguments: ["/chats", "/1000001/chats", "/1000001/projects", "/1000001/settings"])
    func tabRoots(path: String) {
        #expect(properties(path).context == .default)
        #expect(properties(path).pullToRefreshEnabled)
    }

    @Test("keeps Hotwire's historical locations")
    func historicalLocations() {
        #expect(properties("/recede_historical_location").presentation == .pop)
        #expect(properties("/refresh_historical_location").presentation == .refresh)
        #expect(properties("/resume_historical_location").presentation == Navigation.Presentation.none)
    }
}
