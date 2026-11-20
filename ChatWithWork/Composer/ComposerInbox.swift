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
    /// Files shared into the app that wait for a composer, in order: those
    /// in flight with a page that answers for them aren't among them. Setting
    /// it replaces those waiting.
    static var files: [ComposerFile] {
        get { entries.filter { $0.attempt == nil }.map(\.file) }
        set {
            entries.removeAll { $0.attempt == nil }
            entries += newValue.map(Entry.init)
        }
    }

    /// Files shared in, after any still waiting.
    static func share(_ shared: [ComposerFile]) {
        entries += shared.map(Entry.init)
    }

    /// What the web composer on `url` takes now: files when it takes files,
    /// Dictate when its microphone is offered. A Dictate it can't start (no
    /// yes to models yet, locked) is dropped, so it doesn't start a later New
    /// chat listening out of the blue; files wait for one that takes them.
    /// Files kept for the next New chat go only to a composer connecting
    /// after a later visit (`connecting`), never to one that just changed.
    static func take(for state: WebComposerState, at url: URL?, connecting: Bool = true, now: Date = Date()) -> [WebComposerAction] {
        guard let url, AppRoute(url: url).kind == .newChat else { return [] }
        var actions: [WebComposerAction] = []
        let ready = entries.filter { $0.attempt == nil && ($0.afterVisit < 0 || connecting && $0.afterVisit < visits) }
        if !ready.isEmpty, state.acceptsFiles {
            if state.confirmsAttach {
                // The page answers for them (`attached`): they're in flight until it does.
                let id = UUID().uuidString
                for entry in ready {
                    entry.attempt = id
                    entry.sentAt = now
                }
                attempts.append((id, ready.map(\.key)))
                if attempts.count > 50 { attempts.removeFirst(attempts.count - 50) }
                actions.append(.attach(files: ready.map(\.file), id: id))
            } else {
                entries.removeAll { entry in ready.contains { $0 === entry } }
                actions.append(.attach(files: ready.map(\.file)))
            }
        }
        if dictates {
            dictates = false
            if state.dictates { actions.append(.dictate) }
        }
        return actions
    }

    /// What a composer was handed and didn't take, for the next one: an
    /// attach that never reached the page waits again at once, files as they
    /// were.
    static func putBack(_ action: WebComposerAction) {
        switch action {
        case .attach(let taken, let id):
            if let id {
                attempts.removeAll { $0.id == id }
                for entry in entries where entry.attempt == id { entry.attempt = nil }
            } else {
                entries.insert(contentsOf: taken.map(Entry.init), at: 0)
            }
        case .dictate: dictates = true
        }
    }

    // MARK: Files the page answers for

    /// A file shared in, with an identity of its own while it waits, so two
    /// shares of the same bytes stay two, and a late answer about one attempt
    /// finds it wherever it is now.
    private final class Entry {
        let key = UUID().uuidString
        let file: ComposerFile
        /// The attach it's in flight with, until the page answers for it.
        var attempt: String?
        var sentAt = Date.distantPast
        /// Kept for a New chat after this visit: an upload that failed, or
        /// came back unanswered, isn't tried again on the same page.
        var afterVisit = -1

        init(_ file: ComposerFile) { self.file = file }
    }

    private static var entries: [Entry] = []
    /// Each attach's files by key, in its order, for the page's answer: kept
    /// a while after they came back unanswered.
    private static var attempts: [(id: String, keys: [String])] = []
    private static var visits = 0

    /// How long files wait for a page's answer: long enough for a large
    /// upload on a slow network; a duplicate after it beats a loss.
    static let unansweredAfter: TimeInterval = 10 * 60

    /// Files in flight, waiting for a page's answer.
    static var unanswered: Int { entries.count(where: { $0.attempt != nil }) }

    /// The page's answer for the attach `id`, file by file in its order.
    /// Taken, `refused` and `removed` leave, wherever the file is now (an
    /// answer that comes after it was given back, or sent again, still
    /// counts). `locked` and `unavailable` wait to be handed again, on this
    /// page once it unlocks; `failed`, a reason not known yet, or no word
    /// wait for the next New chat.
    static func settle(id: String?, results: [AttachedFile]) {
        guard let id, let index = attempts.firstIndex(where: { $0.id == id }) else { return }
        let keys = attempts.remove(at: index).keys
        for (offset, key) in keys.enumerated() {
            guard let entry = entries.first(where: { $0.key == key }) else { continue }
            let result = offset < results.count ? results[offset] : nil
            if let result, result.taken || ["refused", "removed"].contains(result.reason ?? "") {
                entries.removeAll { $0 === entry }
            } else if entry.attempt != id {
                // Given back or sent again since: its newer attempt decides.
                continue
            } else if ["locked", "unavailable"].contains(result?.reason ?? "") {
                entry.attempt = nil
                entry.afterVisit = -1
            } else {
                entry.attempt = nil
                entry.afterVisit = visits
            }
        }
    }

    /// Gives back files in flight that no answer can come for: all of them,
    /// or those sent before `olderThan`. They wait for the next New chat; a
    /// late answer still takes out what the page took.
    static func returnUnanswered(olderThan: Date? = nil) {
        for entry in entries where entry.attempt != nil && (olderThan.map { entry.sentAt < $0 } ?? true) {
            entry.attempt = nil
            entry.afterVisit = visits
        }
    }

    /// A visit starts: the page that held files in flight may be going, and
    /// every file kept for the next New chat may go to the page it draws.
    static func visitStarted() {
        returnUnanswered()
        visits += 1
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
