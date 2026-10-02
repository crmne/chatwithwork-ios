import HotwireNative
import UIKit

/// `form`: the page's submit button, in the navigation bar.
///
/// Web → native: `connect` with `{title, color?}`, `enableSubmit`,
/// `disableSubmit` (while the form is submitting), and `disconnect`.
/// Native → web: a reply to `connect` when the button is tapped, which clicks
/// the form's submit button. Same as Joe Masilotti's component.
final class FormSubmitComponent: BridgeComponent {
    override nonisolated class var name: String { "form" }

    private weak var item: UIBarButtonItem?

    override func onReceive(message: Message) {
        switch message.event {
        case "connect": show(message)
        case "enableSubmit": item?.isEnabled = true
        case "disableSubmit": item?.isEnabled = false
        case "disconnect": hide()
        default: break
        }
    }

    private func show(_ message: Message) {
        guard let data: FormData = message.data(), let viewController = destinationViewController else { return }

        let action = UIAction(title: data.title) { [weak self] _ in
            self?.reply(with: message)
        }
        let item = UIBarButtonItem(title: data.title, primaryAction: action)
        if #available(iOS 26.0, *) {
            item.style = .prominent
        } else {
            item.style = .done
        }
        item.tintColor = UIColor(hex: data.color)
        item.accessibilityIdentifier = "bridge.form"

        NavigationBarItems.set(item, slot: .form, side: .trailing, on: viewController)
        self.item = item
    }

    private func hide() {
        guard let viewController = destinationViewController else { return }
        NavigationBarItems.set(nil, slot: .form, side: .trailing, on: viewController)
    }
}

nonisolated struct FormData: Decodable, Equatable {
    let title: String
    let color: String?
}
