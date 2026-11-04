import Foundation
import Testing
@testable import ChatWithWork

/// The web views keep to the app-bound domains, where the pages' service
/// worker runs, only when the server they load is one of them.
@Suite("App-bound domains")
struct AppBoundDomainsTests {
    let declared = ["chatwithwork.com", "staging.chatwithwork.com", "chatwithwork.localhost", "localhost"]

    @Test("the hosted servers, the dev server and the playground are bound", arguments: [
        "https://chatwithwork.com", "https://staging.chatwithwork.com/482139075/chats/42",
        "https://chatwithwork.localhost", "http://localhost:8765", "https://CHATWITHWORK.com",
    ])
    func bound(url: String) throws {
        #expect(AppBoundDomains.covers(try #require(URL(string: url)), declared: declared))
    }

    @Test("other servers aren't, so their builds still load without the worker", arguments: [
        "http://192.168.1.20:3000", "https://chatwithwork-apps.com", "https://chatwithwork.b-cdn.net",
        "https://notchatwithwork.com", "https://example.com",
    ])
    func unbound(url: String) throws {
        #expect(!AppBoundDomains.covers(try #require(URL(string: url)), declared: declared))
    }

    @Test("the build lists the hosted servers")
    func declaredInBuild() {
        #expect(AppBoundDomains.declared.contains("chatwithwork.com"))
        #expect(AppBoundDomains.declared.contains("staging.chatwithwork.com"))
        #expect(AppBoundDomains.declared.count <= 10, "WebKit reads at most ten")
    }
}
