import HotwireNative
import UIKit

/// `button`: a navigation bar button that clicks a web element.
///
/// Web → native: `left` or `right` with `{title, iosImage?, androidImage?,
/// color?, nativeAction?}`, and `disconnect`. A button whose `nativeAction`
/// is `new-chat` is left out: the shell puts New chat in every bar itself. Native → web: a reply to the `left`/`right`
/// message when the button is tapped. Same as Joe Masilotti's component; one
/// button per page, which can sit beside a menu, a form button and a share
/// button.
final class NavigationButtonComponent: BridgeComponent {
    override nonisolated class var name: String { "button" }

    private var side: NavigationBarItems.Side?

    override func onReceive(message: Message) {
        switch message.event {
        case "left": show(message, on: .leading)
        case "right": show(message, on: .trailing)
        case "disconnect": hide()
        default: break
        }
    }

    private func show(_ message: Message, on side: NavigationBarItems.Side) {
        guard let data: ButtonData = message.data(), let viewController = destinationViewController else { return }
        // The shell's own New chat is in every bar already.
        guard data.nativeAction != ButtonData.newChat else { return hide() }

        if let previous = self.side, previous != side {
            NavigationBarItems.set(nil, slot: .button, side: previous, on: viewController)
        }

        let action = UIAction(title: data.title) { [weak self] _ in
            self?.reply(with: message)
        }

        let item: UIBarButtonItem
        if let image = data.iosImage.flatMap({ UIImage(systemName: $0) }) {
            item = UIBarButtonItem(image: image, primaryAction: action)
            item.accessibilityLabel = data.title
        } else {
            item = UIBarButtonItem(title: data.title, primaryAction: action)
        }
        item.tintColor = UIColor(hex: data.color)
        item.accessibilityIdentifier = "bridge.button"

        NavigationBarItems.set(item, slot: .button, side: side, on: viewController)
        self.side = side
    }

    private func hide() {
        guard let side, let viewController = destinationViewController else { return }
        NavigationBarItems.set(nil, slot: .button, side: side, on: viewController)
        self.side = nil
    }
}

nonisolated struct ButtonData: Decodable, Equatable {
    static let newChat = "new-chat"

    let title: String
    let iosImage: String?
    let color: String?
    let nativeAction: String?
}
