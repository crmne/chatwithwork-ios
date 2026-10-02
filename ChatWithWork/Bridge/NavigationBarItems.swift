import HotwireNative
import ObjectiveC
import UIKit

/// The buttons in a web screen's navigation bar.
///
/// Joe Masilotti's components each set `rightBarButtonItem`, so a page with a
/// button and a menu shows only whichever connected last. Here every source
/// (each bridge component, and the sheet close button) owns one slot, and the
/// bar shows all occupied slots in a fixed order: lower slots sit closer to
/// the bar's outer edge.
enum NavigationBarItems {
    enum Side: Sendable {
        case leading
        case trailing
    }

    enum Slot: Int, Comparable, Sendable {
        /// A sheet's close button, leading.
        case close
        /// A form's submit button, the outermost trailing item.
        case form
        case menu
        case button
        case share

        static func < (lhs: Slot, rhs: Slot) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static func set(_ item: UIBarButtonItem?, slot: Slot, side: Side, on viewController: UIViewController) {
        let store = Store.of(viewController)
        store.items[side, default: [:]][slot] = item
        apply(store, to: viewController.navigationItem)
    }

    static func item(in slot: Slot, side: Side, on viewController: UIViewController) -> UIBarButtonItem? {
        Store.of(viewController).items[side]?[slot]
    }

    /// The close button iOS puts on the leading side of a sheet's first screen.
    static func setCloseButton(on viewController: UIViewController, action: @escaping () -> Void) {
        guard item(in: .close, side: .leading, on: viewController) == nil else { return }
        let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in action() })
        close.accessibilityIdentifier = "sheet.close"
        set(close, slot: .close, side: .leading, on: viewController)
    }

    private static func apply(_ store: Store, to navigationItem: UINavigationItem) {
        let leading = (store.items[.leading] ?? [:]).sorted { $0.key < $1.key }.map(\.value)
        let trailing = (store.items[.trailing] ?? [:]).sorted { $0.key < $1.key }.map(\.value)

        navigationItem.leftItemsSupplementBackButton = true
        navigationItem.setLeftBarButtonItems(leading.isEmpty ? nil : leading, animated: true)
        navigationItem.setRightBarButtonItems(trailing.isEmpty ? nil : trailing, animated: true)
    }

    private final class Store {
        var items: [Side: [Slot: UIBarButtonItem]] = [:]

        private nonisolated(unsafe) static var key: UInt8 = 0

        static func of(_ viewController: UIViewController) -> Store {
            if let store = objc_getAssociatedObject(viewController, &key) as? Store {
                return store
            }
            let store = Store()
            objc_setAssociatedObject(viewController, &key, store, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return store
        }
    }
}

extension BridgeComponent {
    /// The screen this component's page is showing in.
    var destinationViewController: UIViewController? {
        delegate?.destination as? UIViewController
    }
}
