import Foundation
import Testing
@testable import ChatWithWork

/// What the Live Activity draws, from what the server said, and what it must
/// never pretend to know.
@Suite("Open Road")
struct OpenRoadTests {
    typealias State = ChatActivityAttributes.ContentState
    private let start = Date(timeIntervalSince1970: 1000)

    private func road(_ state: State, stale: Bool = false) -> OpenRoad {
        OpenRoad(state: state, startedAt: start, isStale: stale, now: start.addingTimeInterval(60))
    }

    @Test("states follow the phase and what the answer is on")
    func stages() {
        #expect(road(.answering).stage == .starting)
        #expect(road(State(phase: "answering", step: "answer", steps: 0)).stage == .starting)
        #expect(road(State(phase: "answering", step: "answer", steps: 2)).stage == .working)
        #expect(road(State(phase: "answering", step: "search", steps: 1)).stage == .working)
        #expect(road(State(phase: "answering", step: "write", steps: 3)).stage == .writing)
        #expect(road(State(phase: "answering", step: "use", steps: 3, agents: 3)).stage == .agents)
        #expect(road(State(phase: "answering", step: "use", steps: 3, agents: 1)).stage == .working)
        #expect(road(State(phase: "approval_waiting")).stage == .decision)
        #expect(road(State(phase: "input_requested")).stage == .input)
        #expect(road(State(phase: "answered")).stage == .finished)
        #expect(road(State(phase: "failed")).stage == .failed)
        #expect(road(State(phase: "stopped")).stage == .stopped)
        #expect(road(State(phase: "something_new")).stage == .stale)
    }

    @Test("staleness only touches work: an ended state or a wait is still true")
    func staleness() {
        #expect(road(State(phase: "answering", step: "search", steps: 1), stale: true).stage == .stale)
        #expect(road(State(phase: "answered"), stale: true).stage == .finished)
        #expect(road(State(phase: "failed"), stale: true).stage == .failed)
        #expect(road(State(phase: "approval_waiting"), stale: true).stage == .decision)
        #expect(road(State(phase: "input_requested"), stale: true).stage == .input)

        let heard = road(State(phase: "answering", step: "read", steps: 2, heardAt: 2000), stale: true)
        #expect(heard.clock == .hidden)
        #expect(heard.headline.hasPrefix("Last heard"))
        #expect(road(State(phase: "answering", step: "read", steps: 2), stale: true).headline == "Open chat for an update")
    }

    @Test("every step has its face and tool, and a failure a calm face")
    func faces() {
        let poses: [(String, OpenRoad.Face, OpenRoad.Tool?)] = [
            ("answer", .up, nil), ("search", .right, .search), ("list", .left, .list), ("read", .down, .read), ("use", .focus, .use),
            ("plan", .up, .plan), ("run", .focus, .run), ("write", .down, .write), ("ask", .brow, .ask), ("something_new", .up, nil)
        ]
        for (step, face, tool) in poses {
            let drawn = road(State(phase: "answering", step: step, steps: 1))
            #expect(drawn.face == face)
            #expect(drawn.tool == tool)
        }
        #expect(road(.answering).face == .open)
        #expect(road(State(phase: "approval_waiting")).face == .wide)
        #expect(road(State(phase: "answered")).face == .happy)
        #expect(road(State(phase: "failed")).face == .closed)
        #expect(road(State(phase: "stopped")).face == .flat)
    }

    @Test("the trail is what happened, one tick a step, refused ones marked")
    func trail() {
        let ticks = OpenRoad.ticks(trail: "xrUslpaw", steps: 8)
        #expect(ticks.map(\.refused) == [false, false, true, false, false, false, false, false])
        #expect(OpenRoad.ticks(trail: String(repeating: "s", count: 60), steps: 60).count == OpenRoad.maxTicks)
    }

    @Test("a tick is as tall as the time its step took, in four sizes")
    func pace() {
        #expect(OpenRoad.ticks(trail: "srUx", pace: "1234", steps: 4).map(\.height) == [6, 13, 21, 29])
        #expect(OpenRoad.ticks(trail: "srUx", pace: "4321", steps: 4).map(\.refused) == [false, false, true, false])
        let drawn = road(State(phase: "answering", step: "read", steps: 2, trail: "sr", pace: "41"))
        #expect(drawn.ticks.map(\.height) == [29, 6])
    }

    @Test("pace is cut with the trail, keeping the newest of both")
    func paceTruncation() {
        let trail = String(repeating: "s", count: OpenRoad.maxTicks) + "rr"
        let pace = "44" + String(repeating: "1", count: OpenRoad.maxTicks - 1) + "3"
        let ticks = OpenRoad.ticks(trail: trail, pace: pace, steps: 50)
        #expect(ticks.count == OpenRoad.maxTicks)
        #expect(ticks.first?.height == 6)
        #expect(ticks.last?.height == 21)
    }

    @Test("with no usable pace every tick is one even height, whatever its kind")
    func evenTicks() {
        let even = Array(repeating: OpenRoad.evenHeight, count: 4)
        #expect(OpenRoad.ticks(trail: "xrpw", steps: 4).map(\.height) == even)
        #expect(OpenRoad.ticks(trail: "xrpw", pace: "123", steps: 4).map(\.height) == even)
        #expect(OpenRoad.ticks(trail: "xrpw", pace: "12345", steps: 4).map(\.height) == even)
        #expect(OpenRoad.ticks(trail: "xrpw", pace: "12x4", steps: 4).map(\.height) == even)
        #expect(OpenRoad.ticks(trail: "xrpw", pace: "1205", steps: 4).map(\.height) == even)
    }

    @Test("pace comes in the content state's own key")
    func paceDecodes() throws {
        let json = Data(#"{"phase":"answering","trail":"sr","pace":"14"}"#.utf8)
        #expect(try JSONDecoder().decode(State.self, from: json).pace == "14")
    }

    @Test("a wait faces you and draws no tool: the card it holds says what about")
    func waits() {
        #expect(road(State(phase: "approval_waiting", step: "use", service: "slack")).face == .wide)
        #expect(road(State(phase: "approval_waiting", step: "use", service: "slack")).tool == nil)
        #expect(road(State(phase: "input_requested", step: "ask")).face == .brow)
        #expect(road(State(phase: "input_requested", step: "ask")).tool == nil)
    }

    @Test("an older server gets even ticks from its real count, and no stops")
    func legacy() {
        let drawn = road(State(phase: "answering", message: "Searching Drive", step: "search", steps: 7))
        #expect(drawn.isLegacy)
        #expect(drawn.ticks == Array(repeating: OpenRoad.Tick(height: OpenRoad.evenHeight), count: 7))
        #expect(drawn.stops.isEmpty)
        #expect(drawn.splitHeadline == nil)
        #expect(drawn.headline == "Searching Drive")
        #expect(drawn.clock == .running(since: start))
        #expect(road(State(phase: "answering", step: "search", steps: 500)).ticks.count == OpenRoad.maxTicks)
    }

    @Test("the origin scrolls off with a deep trail")
    func deep() {
        #expect(!road(State(phase: "answering", step: "read", steps: 23, trail: String(repeating: "r", count: 23))).isDeep)
        #expect(road(State(phase: "answering", step: "read", steps: 24, trail: String(repeating: "r", count: 24))).isDeep)
    }

    @Test("stops are services behind the bot, newest kept, the current one left out")
    func stops() {
        #expect(OpenRoad.stops(services: ["slack", "google_drive"], current: "google_drive") == ["slack"])
        #expect(OpenRoad.stops(services: ["a", "b", "c", "d", "e", "f", "g"], current: nil) == ["c", "d", "e", "f", "g"])
        #expect(OpenRoad.stops(services: nil, current: nil).isEmpty)
    }

    @Test("logos are for built-in services; anything else is a neutral dot, and never named")
    func logos() {
        #expect(OpenRoad.hasLogo("slack"))
        #expect(OpenRoad.hasLogo("mcp"))
        #expect(OpenRoad.hasLogo("computer"))
        #expect(!OpenRoad.hasLogo("something_new"))
        #expect(OpenRoad.serviceNames["mcp"] == nil)
        #expect(OpenRoad.serviceNames["computer"] == nil)
    }

    @Test("the logo sits inside the words that name its service")
    func headline() {
        func split(_ message: String, _ service: String) -> OpenRoad {
            road(State(phase: "answering", message: message, step: "read", steps: 1, service: service))
        }
        #expect(split("Searching Drive", "google_drive").splitHeadline?.verb == "Searching")
        #expect(split("Searching Drive", "google_drive").splitHeadline?.name == "Drive")
        #expect(split("Reading 12 files in HubSpot", "hubspot").splitHeadline?.verb == "Reading 12 files")
        #expect(split("Searching an MCP server", "mcp").splitHeadline == nil)
        #expect(split("Drive", "google_drive").splitHeadline == nil)
    }

    @Test("the clock runs from the server's start, a wait's clock from the wait, and an end stands still")
    func clocks() {
        let server = Date(timeIntervalSince1970: 500)
        #expect(road(State(phase: "answering", step: "read", steps: 1, startedAt: 500)).clock == .running(since: server))
        #expect(road(State(phase: "approval_waiting", startedAt: 500, waitingSince: 900)).clock == .running(since: Date(timeIntervalSince1970: 900)))
        #expect(road(State(phase: "approval_waiting", startedAt: 500)).clock == .running(since: server))
        #expect(road(State(phase: "answered", startedAt: 500, heardAt: 918)).clock == .fixed(418))
        #expect(road(State(phase: "stopped", startedAt: 500, heardAt: 700)).clock == .fixed(200))
    }

    @Test("no total is made up where the server gave none, and a failure shows none")
    func noInventedTotals() {
        #expect(road(State(phase: "answered")).clock == .hidden)
        #expect(road(State(phase: "answered", heardAt: 918)).clock == .hidden)
        #expect(road(State(phase: "failed", startedAt: 500, heardAt: 700)).clock == .hidden)
    }

    @Test("an end push that carries no steps still draws a road, without a count")
    func bareEnd() {
        let drawn = road(State(phase: "answered", message: "Your answer is ready.", startedAt: 500, heardAt: 918))
        #expect(drawn.stage == .finished)
        #expect(drawn.ticks.isEmpty)
        #expect(drawn.stepsLabel == nil)
    }

    @Test("bands appear where someone is needed or it failed")
    func bands() {
        #expect(road(State(phase: "approval_waiting")).hasBand)
        #expect(road(State(phase: "input_requested")).hasBand)
        #expect(road(State(phase: "failed")).hasBand)
        #expect(!road(State(phase: "answered")).hasBand)
        #expect(!road(State(phase: "stopped")).hasBand)
        #expect(road(State(phase: "approval_waiting")).bandAction == "Review")
        #expect(road(State(phase: "input_requested")).bandAction == "Reply")
        #expect(road(State(phase: "failed")).bandAction == "Open")
    }

    @Test("clock text keeps its shape past an hour")
    func clockText() {
        #expect(OpenRoad.clockText(48) == "0:48")
        #expect(OpenRoad.clockText(418) == "6:58")
        #expect(OpenRoad.clockText(3703) == "1:01:43")
    }

    @Test("one spoken label says what a face or colour shows")
    func accessibility() {
        let now = start.addingTimeInterval(60)
        let working = road(State(phase: "answering", message: "Searching Drive", step: "search", steps: 5)).accessibilityLabel(organization: "Northwind Studio", now: now)
        #expect(working.hasPrefix("Chat with Work, Northwind Studio. Searching Drive. 5 steps. Running"))
        let decision = road(State(phase: "approval_waiting", service: "slack")).accessibilityLabel(organization: "Northwind Studio", now: now)
        #expect(decision.hasPrefix("A change in Slack is waiting for your approval."))
        #expect(decision.hasSuffix("Double-tap to review."))
        #expect(road(State(phase: "failed")).accessibilityLabel(organization: "Northwind Studio") == "The answer couldn't finish.")
        #expect(road(State(phase: "input_requested")).accessibilityLabel(organization: "Northwind Studio") == "A question is waiting for your answer.")
    }

    @Test("nothing a person reads claims a percentage, or an end ahead of it")
    func honesty() {
        for phase in ["answering", "approval_waiting", "input_requested", "answered", "failed", "stopped"] {
            let drawn = road(State(phase: phase, message: "Working", step: "read", steps: 4, trail: "srlr"))
            #expect(!drawn.headline.contains("%"))
            #expect(!(drawn.stepsLabel ?? "").contains("%"))
        }
    }
}
