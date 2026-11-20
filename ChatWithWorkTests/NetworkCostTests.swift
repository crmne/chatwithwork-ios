import Testing
@testable import ChatWithWork

/// What the pages hear of the network, so they load ahead only on one that costs nothing.
@Suite("Network cost")
struct NetworkCostTests {
    @Test("an expensive path is metered, a constrained one is Low Data Mode, and only neither is free")
    func mapping() {
        #expect(NetworkCost.cost(expensive: false, constrained: false).isFree)
        #expect(NetworkCost.cost(expensive: true, constrained: false) == .init(metered: true, constrained: false))
        #expect(!NetworkCost.cost(expensive: true, constrained: false).isFree)
        #expect(NetworkCost.cost(expensive: false, constrained: true) == .init(metered: false, constrained: true))
        #expect(!NetworkCost.cost(expensive: false, constrained: true).isFree)
    }

    @Test("tells the page as window.chatWithWorkNetwork")
    func script() {
        let script = NetworkCost.script(.init(metered: true, constrained: false))
        #expect(script.hasPrefix(NetworkCost.marker))
        #expect(script.hasSuffix("window.chatWithWorkNetwork = { metered: true, constrained: false };"))
        #expect(SidebarPage.preloadScript.contains("window.chatWithWork?.preload?.()"))
    }
}
