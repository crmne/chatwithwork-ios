import HotwireNative
import UIKit

/// `menu`: a navigation bar button that opens a native menu whose items click
/// web elements.
///
/// Web → native: `connect` with `{items: [{title, iosImage?, androidImage?,
/// destructive?, checked?}], color?}`, and `disconnect`.
/// Native → web: a reply to `connect` with `{index}` when an item is chosen.
///
/// Joe Masilotti's contract, plus optional fields: `side` ("left" or
/// "right", default right), `label`, `iosImage` (the button's symbol, default
/// an ellipsis), `header` (a title above the items), and per item `checked`.
///
/// A menu with `side: "left"` or a `header` is a chooser, like the
/// organization switcher: its button shows `label` as text (the current
/// choice). Any other menu is a symbol, with `label` as its accessibility
/// label. The Android app draws the same two kinds from the same rule.
final class NavigationMenuComponent: BridgeComponent {
    override nonisolated class var name: String { "menu" }

    private var side: NavigationBarItems.Side?

    override func onReceive(message: Message) {
        switch message.event {
        case "connect": show(message)
        case "disconnect": hide()
        default: break
        }
    }

    private func show(_ message: Message) {
        guard let data: MenuData = message.data(), let viewController = destinationViewController else { return }

        let side: NavigationBarItems.Side = data.side == "left" ? .leading : .trailing
        if let previous = self.side, previous != side {
            NavigationBarItems.set(nil, slot: .menu, side: previous, on: viewController)
        }

        let actions = data.items.enumerated().map { index, item in
            return UIAction(
                title: item.title,
                image: item.iosImage.flatMap { UIImage(systemName: $0) },
                attributes: item.destructive == true ? .destructive : [],
                state: item.checked == true ? .on : .off
            ) { [weak self] _ in
                self?.reply(with: message.replacing(data: MenuSelection(index: index)))
            }
        }

        let menu = UIMenu(title: data.header ?? "", children: actions)
        let item: UIBarButtonItem
        if data.isChooser, let label = data.label, !label.isEmpty {
            item = UIBarButtonItem(title: label, menu: menu)
            item.accessibilityLabel = [data.header, label].compactMap { $0 }.joined(separator: ", ")
        } else {
            item = UIBarButtonItem(image: UIImage(systemName: data.iosImage ?? Self.defaultSymbol), menu: menu)
            item.accessibilityLabel = data.label ?? String(localized: "More")
        }
        item.tintColor = UIColor(hex: data.color)
        item.accessibilityIdentifier = "bridge.menu"

        NavigationBarItems.set(item, slot: .menu, side: side, on: viewController)
        self.side = side
    }

    private func hide() {
        guard let side, let viewController = destinationViewController else { return }
        NavigationBarItems.set(nil, slot: .menu, side: side, on: viewController)
        self.side = nil
    }

    private static var defaultSymbol: String {
        if #available(iOS 26.0, *) { "ellipsis" } else { "ellipsis.circle" }
    }
}

nonisolated struct MenuData: Decodable, Equatable {
    nonisolated struct Item: Decodable, Equatable {
        let title: String
        let iosImage: String?
        let destructive: Bool?
        let checked: Bool?
    }

    let items: [Item]
    let color: String?
    let side: String?
    let label: String?
    let iosImage: String?
    let header: String?

    /// A menu for picking one thing (the organization switcher), not a page's actions.
    var isChooser: Bool { side == "left" || header != nil }
}

nonisolated struct MenuSelection: Codable, Equatable {
    let index: Int
}
