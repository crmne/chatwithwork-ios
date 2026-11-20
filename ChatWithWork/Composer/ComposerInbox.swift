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
    static func take(for state: WebComposerState, at url: URL?) -> [WebComposerAction] {
        guard let url, AppRoute(url: url).kind == .newChat else { return [] }
        var actions: [WebComposerAction] = []
        if !files.isEmpty, state.acceptsFiles {
            actions.append(.attach(files: files))
            files = []
        }
        if dictates {
            dictates = false
            if state.dictates { actions.append(.dictate) }
        }
        return actions
    }
}
