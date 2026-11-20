import Foundation

/// What came from outside the page for the next New chat's composer, the
/// app's own (`ComposerController`) or the web's (`WebComposerComponent`):
/// files shared into the app, a share's words, and a widget's or a
/// shortcut's Dictate. Both share and widget open New chat, so only a New
/// chat's composer takes them, never a chat on screen whose composer
/// happens to connect again first.
@MainActor
enum ComposerInbox {
    /// A widget's or a shortcut's "Dictate": the next composer that connects
    /// starts listening.
    static var dictates = false
    /// Words shared into the app, for the app's own composer. The web one
    /// gets them in New chat's address (`/chats/new?text=`).
    static var text: String?
    /// Files shared into the app, handed to the next composer that connects.
    static var files: [ComposerFile] = []

    /// What the web composer on `url` takes now, emptying the inbox of it:
    /// files when it takes files, Dictate when its microphone is offered. A
    /// Dictate it can't start (no yes to models yet, locked) is dropped, so
    /// it doesn't start a later New chat listening out of the blue; files
    /// wait for one that takes them.
    static func take(for state: WebComposerState, at url: URL?, now: Date = Date()) -> [WebComposerAction] {
        guard let url, AppRoute(url: url).kind == .newChat else { return [] }
        var actions: [WebComposerAction] = []
        if !files.isEmpty, state.acceptsFiles {
            if state.confirmsAttach {
                // The page answers for them (`attached`): they're in flight until it does.
                let id = UUID().uuidString
                inFlight[id] = InFlight(files: files, sentAt: now)
                actions.append(.attach(files: files, id: id))
            } else {
                actions.append(.attach(files: files))
            }
            files = []
        }
        if dictates {
            dictates = false
            if state.dictates { actions.append(.dictate) }
        }
        return actions
    }

    /// What a composer was handed and didn't take, for the next one.
    static func putBack(_ action: WebComposerAction) {
        switch action {
        case .attach(let taken, let id):
            if let id { inFlight[id] = nil }
            files = taken + files
        case .dictate: dictates = true
        }
    }

    // MARK: Files the page answers for

    /// Files handed to a page that says which it took (`confirmsAttach`), by
    /// the id their `attach` carried, until its `attached` arrives
    /// (`settle`). The page answers every attach while it lives, so only a
    /// page gone away leaves them unanswered (`returnUnanswered`).
    private struct InFlight {
        let files: [ComposerFile]
        let sentAt: Date
    }

    private static var inFlight: [String: InFlight] = [:]
    /// Files given back before their answer came, so a late answer can still
    /// take out what the page took.
    private static var returned: [(id: String, files: [ComposerFile])] = []

    /// How long files wait for a page's answer: long enough for a large
    /// upload on a slow network; a duplicate after it beats a loss.
    static let unansweredAfter: TimeInterval = 10 * 60

    /// Files in flight, waiting for a page's answer.
    static var unanswered: Int { inFlight.values.reduce(0) { $0 + $1.files.count } }

    /// The page's answer for the attach `id`: each file it took, or let go
    /// (`refused`, `removed`), leaves; any other waits again for the next New
    /// chat, ahead of newer ones. An answer for files already given back
    /// takes the same files out of those waiting.
    static func settle(id: String?, results: [AttachedFile]) {
        guard let id else { return }
        if let sent = inFlight.removeValue(forKey: id) {
            files = sent.files.enumerated().filter { keeps(results[safe: $0.offset]) }.map(\.element) + files
            return
        }
        guard let index = returned.firstIndex(where: { $0.id == id }) else { return }
        let given = returned.remove(at: index).files
        for (offset, file) in given.enumerated() where !keeps(results[safe: offset]) {
            if let at = files.firstIndex(of: file) { files.remove(at: at) }
        }
    }

    /// Gives back files in flight that no answer can come for: all of them
    /// (the page went away), or those sent before `olderThan`.
    static func returnUnanswered(olderThan: Date? = nil) {
        let stale = inFlight.filter { olderThan == nil || $0.value.sentAt < olderThan! }
        for (id, flight) in stale.sorted(by: { $0.value.sentAt < $1.value.sentAt }) {
            inFlight[id] = nil
            returned.append((id, flight.files))
            files = flight.files + files
        }
        if returned.count > 20 { returned.removeFirst(returned.count - 20) }
    }

    private static func keeps(_ result: AttachedFile?) -> Bool {
        guard let result else { return true }
        return !result.taken && !["refused", "removed"].contains(result.reason ?? "")
    }
}

/// One file of the page's `attached`: whether it was taken, and why not
/// (`locked`, `unavailable`, `failed`, `refused`, `removed`, or a later one).
nonisolated struct AttachedFile: Decodable, Equatable, Sendable {
    let name: String?
    let taken: Bool
    let reason: String?

    init(name: String?, taken: Bool, reason: String? = nil) {
        self.name = name
        self.taken = taken
        self.reason = reason
    }
}

/// The page's `attached`, once every file of an `attach` has settled: one
/// entry per file, in the attach's order.
nonisolated struct AttachedAnswer: Decodable, Sendable {
    let id: String?
    let taken: Bool
    let files: [AttachedFile]

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try? values.decodeIfPresent(String.self, forKey: .id)
        taken = try values.decodeIfPresent(Bool.self, forKey: .taken) ?? false
        files = try values.decodeIfPresent([AttachedFile].self, forKey: .files) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, taken, files
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
