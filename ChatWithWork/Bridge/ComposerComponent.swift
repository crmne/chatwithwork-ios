import HotwireNative
import UIKit

/// `composer`: the app draws the chat's composer and drives the web one,
/// which stays in the page hidden (native.css) so every rule it carries
/// holds (docs/server-contract.md, "The composer").
///
/// Web → native: `connect` with the composer's state, then `state` whenever
/// it changes. Each new web composer (a chat draws it again as an answer
/// starts and ends) connects again. Native → web: a reply to the latest
/// `connect`, `{action, ...}`: `send`, `stop`, `model`, `webSearch`,
/// `attach`, `remove` or `text`.
final class ComposerComponent: BridgeComponent {
    override nonisolated class var name: String { "composer" }

    override func onReceive(message: Message) {
        guard message.event == "connect" || message.event == "state",
              let state: ComposerState = message.data(),
              let screen = destinationViewController as? VisitableViewController
        else { return }

        let composer = ComposerController.on(screen)
        composer.send = { [weak self] action in
            guard let self else { return }
            Task { _ = try? await self.reply(to: "connect", with: action) }
        }
        composer.onState = { state in
            LiveActivities.shared.noteState(state, chatURL: message.metadata.flatMap { URL(string: $0.url) })
        }
        composer.update(state, connected: message.event == "connect")
    }
}
