import Foundation
import HotwireNative
import Testing
@testable import ChatWithWork

/// What the sidebar opens, with the bundled path configuration: a place at
/// the root, or a form over the screen.
@Suite("Places")
struct PlacesTests {
    private let configuration: PathConfiguration = {
        let url = Bundle.main.url(forResource: "path-configuration", withExtension: "json")!
        return PathConfiguration(sources: [.file(url)])
    }()

    private func opening(_ path: String) -> PathProperties {
        Places.opening(configuration.properties(for: path))
    }

    @Test("replaces the root with every page the sidebar opens", arguments: [
        "/1000001/chats/42", "/1000001/chats/new", "/1000001/decisions?decision=t7", "/1000001/bots", "/1000001/settings",
        "/1000001/bots/7", "/1000001/projects/3", "/1000001/settings?tab=assistant&project=3", "/accounts"
    ])
    func places(path: String) {
        #expect(opening(path).presentation == .replaceRoot)
        #expect(opening(path).context == .default)
    }

    @Test("a notification's page starts the navigator as the root place; a form doesn't", arguments: [
        ("/1000001/chats/42", true), ("/1000001/bots/7", true), ("/1000001/settings", true), ("/1000001/projects/new", false)
    ])
    func startingPlace(path: String, starts: Bool) throws {
        let url = try #require(URL(string: "https://chatwithwork.com" + path))
        let place = SidebarShell.startingPlace(url, properties: configuration.properties(for: path))
        #expect((place != nil) == starts)
        if let place {
            #expect(place.url == url)
            #expect(place.properties.presentation == .replaceRoot)
        }
    }

    @Test("brings forms and pickers up as sheets over the screen", arguments: [
        "/1000001/projects/new", "/1000001/chats/42/edit", "/1000001/chats/42/section/edit", "/1000001/bots/new"
    ])
    func forms(path: String) {
        #expect(opening(path).context == .modal)
        #expect(opening(path).presentation == .default)
    }
}
