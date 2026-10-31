import ActivityKit
import Foundation

/// One answer as the server names it (docs/server-contract.md, "Live
/// Activities"): opaque, and nothing from the chat. Older servers name none.
nonisolated struct LiveRun: Equatable, Sendable {
    let id: String
    let revision: Int64
    let startedAt: Date?

    init?(id: String?, revision: Int64?, startedAt: Int64?) {
        guard let id, !id.isEmpty else { return nil }
        self.id = id
        self.revision = revision ?? 0
        self.startedAt = startedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

/// What to do about a chat's activities when its composer says it works.
nonisolated enum LiveActivityStart: Equatable, Sendable {
    /// Nothing: this run shows, or the person dismissed it.
    case none
    case keep(id: String)
    /// A new activity, once these older ones are gone.
    case start(replacing: [String])

    struct Existing: Equatable, Sendable {
        let id: String
        /// nil for an activity started before the server named runs.
        let run: String?
        /// Working or stale, not ended and only left on the Lock Screen.
        let isLive: Bool
    }

    static func choose(for run: LiveRun?, existing: [Existing], dismissed: Bool) -> LiveActivityStart {
        guard let run else { return existing.isEmpty ? .start(replacing: []) : .none }
        if dismissed { return .none }
        if let same = existing.first(where: { $0.isLive && ($0.run == run.id || $0.run == nil) }) { return .keep(id: same.id) }
        return .start(replacing: existing.map(\.id))
    }
}

/// How an activity left. iOS says `.dismissed` for all of them, so a person
/// clearing a working card is what's left once the app's own endings and the
/// ending shown after the server's end are ruled out.
nonisolated enum LiveActivityEnding {
    static func isPersonsDismissal(from previous: ActivityState, to state: ActivityState, endedByApp: Bool) -> Bool {
        state == .dismissed && !endedByApp && (previous == .active || previous == .stale)
    }
}

/// The runs whose card the person dismissed, kept across launches for as
/// long as a run can last and cleared with the session, so nothing of one
/// identity reaches the next.
@MainActor
struct LiveRunDismissals {
    private static let key = "live-run-dismissals"
    /// Apple keeps an activity at most eight hours.
    static let lifetime: TimeInterval = 8 * 60 * 60

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contains(_ run: String, now: Date = .now) -> Bool {
        current(now: now)[run] != nil
    }

    func insert(_ run: String, now: Date = .now) {
        var runs = current(now: now)
        runs[run] = now.timeIntervalSince1970
        defaults.set(runs, forKey: Self.key)
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.key)
    }

    private func current(now: Date) -> [String: TimeInterval] {
        let runs = defaults.dictionary(forKey: Self.key) as? [String: TimeInterval] ?? [:]
        return runs.filter { now.timeIntervalSince1970 - $0.value < Self.lifetime }
    }
}

/// Telling the server an activity's push token, tried again while the server
/// can't be reached, and stopped the moment its task is cancelled, as signing
/// out does: one more try would carry the old session's cookies.
nonisolated enum LiveActivityRegistration {
    enum Outcome: Equatable, Sendable {
        case registered
        /// 409: the run is over, and nothing would ever end this activity.
        case runOver
        case gaveUp
    }

    static let attempts = 6

    static func attempt(send: () async -> Int?, pause: (Int) async -> Void) async -> Outcome {
        for attempt in 0..<attempts {
            if attempt > 0 { await pause(attempt) }
            if Task.isCancelled { return .gaveUp }
            guard let status = await send() else { continue }
            if status == 409 { return .runOver }
            // The server refusing it (4xx) won't change by trying again.
            if status < 500 { return .registered }
        }
        return .gaveUp
    }
}
