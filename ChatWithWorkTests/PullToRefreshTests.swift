import Testing
@testable import ChatWithWork

@MainActor
@Suite("Pull to refresh")
struct PullToRefreshTests {
    @Test("only the latest pull may end the spinner or fall back")
    func latestPullWins() {
        let handler = PullToRefresh(controller: nil)
        let first = handler.begin()
        #expect(handler.isCurrent(first))
        let second = handler.begin()
        #expect(!handler.isCurrent(first), "an earlier pull settling late leaves the newer one alone")
        #expect(handler.isCurrent(second))
    }
}
