import Foundation
import Testing
@testable import ChatWithWork

@MainActor
@Suite("Sidebar opening")
struct SidebarOpeningTests {
    private let projects = URL(string: "https://chatwithwork.com/482139075/projects")!

    @Test("The screen the sidebar opened takes it")
    func screenTakesIt() {
        let opening = SidebarOpening()
        opening.opening(projects)

        #expect(opening.take(projects))
    }

    @Test("The same page opened again by a link doesn't")
    func onlyOnce() {
        let opening = SidebarOpening()
        opening.opening(projects)
        _ = opening.take(projects)

        #expect(!opening.take(projects))
    }

    @Test("Another screen ends it")
    func anotherScreenEndsIt() {
        let opening = SidebarOpening()
        opening.opening(projects)

        #expect(!opening.take(URL(string: "https://chatwithwork.com/482139075/bots")))
        #expect(!opening.take(projects))
    }

    @Test("Nothing is open until the sidebar opens it")
    func nothingOpen() {
        #expect(!SidebarOpening().take(projects))
        #expect(!SidebarOpening().take(nil))
    }
}
