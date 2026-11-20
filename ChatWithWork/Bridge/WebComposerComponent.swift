import HotwireNative
import UIKit

/// `web-composer`: the page's own composer, which the app shows rather than
/// drawing one (`BridgeRegistry.drawsComposer` off; docs/server-contract.md,
/// "The web composer"). The page draws and sends everything; the app only
/// follows whether an answer works, for its Live Activity, and hands the
/// composer what came from outside the page.
///
/// Web → native: `connect` with `{working, waiting, run, revision,
/// startedAt, mark, csrfToken, acceptsFiles, dictates}`, then `state` with
/// the same keys whenever they change. Each composer the chat draws again
/// connects again. Native → web, replies to the latest `connect`:
/// `{action: "attach", files}` (files shared into the app) and
/// `{action: "dictate"}` (a widget's or a shortcut's Dictate).
final class WebComposerComponent: BridgeComponent {
    override nonisolated class var name: String { "web-composer" }

    /// Every composer connected on a screen now, to hand a New chat already
    /// on screen what a share or a widget brings without a visit.
    private static let connected = NSHashTable<WebComposerComponent>.weakObjects()

    private var state: WebComposerState?
    private var url: URL?

    override func onReceive(message: Message) {
        if message.event == "attached" {
            if let answer: AttachedAnswer = message.data() { ComposerInbox.settle(id: answer.id, results: answer.files) }
            return
        }
        guard message.event == "connect" || message.event == "state",
              let state: WebComposerState = message.data() else { return }
        let url = message.metadata.flatMap { URL(string: $0.url) }
        self.state = state
        self.url = url
        LiveActivities.shared.noteState(state, chatURL: url)
        // Files a page went quiet on for too long wait again for the next New chat.
        ComposerInbox.returnUnanswered(olderThan: Date().addingTimeInterval(-ComposerInbox.unansweredAfter))

        if message.event == "connect" {
            Self.connected.add(self)
            takeInbox()
        } else if state.acceptsFiles, !ComposerInbox.files.isEmpty {
            // Shared files that waited for this composer to unlock.
            takeInbox()
        }
    }

    /// Hands the composer what waits for it in `ComposerInbox`. What the
    /// page doesn't take (no bridge, an error) goes back into the inbox, and
    /// so do files when the composer said it was locked by the time the
    /// reply goes: the page drops an `attach` while locked, saying nothing.
    /// A lock that comes between the reply and the page acting on it can't
    /// be seen from here; only the page could say it took the files.
    func takeInbox() {
        guard let state else { return }
        for action in ComposerInbox.take(for: state, at: url) {
            Task {
                // Files wait for a composer that takes them; a Dictate it can't start is dropped (`take`).
                guard stillTakes(action) else {
                    if case .attach = action { ComposerInbox.putBack(action) }
                    return
                }
                let delivered = (try? await reply(to: "connect", with: action)) ?? false
                if !delivered { ComposerInbox.putBack(action) }
            }
        }
    }

    /// Whether the composer's latest word still lets it take `action`, on
    /// New chat still: a composer that connected again elsewhere doesn't.
    private func stillTakes(_ action: WebComposerAction) -> Bool {
        guard let state, let url, AppRoute(url: url).kind == .newChat else { return false }
        switch action {
        case .attach: return state.acceptsFiles
        case .dictate: return state.dictates
        }
    }

    /// The web composer of the New chat on top of `navigator`, with nothing
    /// over it.
    static func onNewChat(_ navigator: UINavigationController) -> WebComposerComponent? {
        guard navigator.presentedViewController == nil, let top = navigator.topViewController,
              let routed = top.routedURL, AppRoute(url: routed).kind == .newChat else { return nil }
        return connected.allObjects.last { $0.destinationViewController === top && $0.url.map { AppRoute(url: $0).kind == .newChat } == true }
    }
}

/// What the web composer says about itself to `web-composer`.
nonisolated struct WebComposerState: Decodable, Equatable, Sendable, LiveComposerState {
    let working: Bool
    let waiting: Bool
    let run: String?
    let revision: Int64?
    let startedAt: Int64?
    /// Who's at work on that answer, for the Live Activity: `chat` or `bot`.
    let mark: String?
    let csrfToken: String?
    /// False while the composer is locked.
    let acceptsFiles: Bool
    /// The page answers each `attach` with `attached`; absent from older
    /// pages, which say nothing.
    let confirmsAttach: Bool
    /// Whether the composer's microphone is offered now.
    let dictates: Bool

    var liveRun: LiveRun? { LiveRun(id: run, revision: revision, startedAt: startedAt) }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        working = try values.decodeIfPresent(Bool.self, forKey: .working) ?? false
        waiting = try values.decodeIfPresent(Bool.self, forKey: .waiting) ?? false
        run = try values.decodeIfPresent(String.self, forKey: .run)
        revision = try values.decodeIfPresent(Int64.self, forKey: .revision)
        startedAt = try values.decodeIfPresent(Int64.self, forKey: .startedAt)
        mark = try values.decodeIfPresent(String.self, forKey: .mark)
        csrfToken = try values.decodeIfPresent(String.self, forKey: .csrfToken)
        acceptsFiles = try values.decodeIfPresent(Bool.self, forKey: .acceptsFiles) ?? false
        dictates = try values.decodeIfPresent(Bool.self, forKey: .dictates) ?? false
        confirmsAttach = try values.decodeIfPresent(Bool.self, forKey: .confirmsAttach) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case working, waiting, run, revision, startedAt, mark, csrfToken, acceptsFiles, dictates, confirmsAttach
    }
}

/// What the app tells the web composer, as a reply to its latest `connect`.
nonisolated enum WebComposerAction: Encodable, Equatable, Sendable {
    /// `id`, for a page that answers with `attached` (`confirmsAttach`).
    case attach(files: [ComposerFile], id: String? = nil)
    case dictate

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .attach(let files, let id):
            try values.encode("attach", forKey: .action)
            try values.encodeIfPresent(id, forKey: .id)
            try values.encode(files, forKey: .files)
        case .dictate:
            try values.encode("dictate", forKey: .action)
        }
    }

    private enum Key: String, CodingKey {
        case action, id, files
    }
}
