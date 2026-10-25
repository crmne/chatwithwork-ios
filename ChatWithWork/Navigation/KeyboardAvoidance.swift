import HotwireNative
import ObjectiveC
import UIKit

/// Keeps web pages above the keyboard by resizing the web view rather than
/// letting WebKit scroll the page under the navigation bar. The web
/// composer is docked to the bottom of the viewport, so it rides on top of
/// the keyboard and the conversation above it keeps its full height. Where
/// the app draws the composer itself (ComposerController), the web view ends
/// above it, and the composer rides on the keyboard instead.
enum KeyboardAvoidance {
    private nonisolated(unsafe) static var key: UInt8 = 0

    static func install(on controller: VisitableViewController) {
        guard let container = controller.viewIfLoaded else { return }
        let visitableView = controller.visitableView

        let bottom = container.constraints.first { constraint in
            (constraint.firstItem === visitableView && constraint.firstAttribute == .bottom && constraint.secondItem === container)
                || (constraint.secondItem === visitableView && constraint.secondAttribute == .bottom && constraint.firstItem === container)
        }
        guard let bottom else { return }

        let guide = container.keyboardLayoutGuide
        guide.usesBottomSafeArea = false
        bottom.isActive = false
        let toKeyboard = visitableView.bottomAnchor.constraint(equalTo: guide.topAnchor)
        toKeyboard.isActive = true
        objc_setAssociatedObject(controller, &key, toKeyboard, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Docks `accessory` (the native composer) above the keyboard, or above
    /// the home indicator while it's down, with the web view ending above it.
    static func dock(_ accessory: UIView, on controller: VisitableViewController) {
        guard let container = controller.viewIfLoaded, accessory.superview == nil else { return }
        (objc_getAssociatedObject(controller, &key) as? NSLayoutConstraint)?.isActive = false

        let guide = container.keyboardLayoutGuide
        guide.usesBottomSafeArea = true
        accessory.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(accessory)
        // As wide as the screen on a phone; on an iPad, as wide as the conversation's column.
        let fullWidth = accessory.widthAnchor.constraint(equalTo: container.safeAreaLayoutGuide.widthAnchor)
        fullWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            accessory.leadingAnchor.constraint(greaterThanOrEqualTo: container.safeAreaLayoutGuide.leadingAnchor),
            accessory.trailingAnchor.constraint(lessThanOrEqualTo: container.safeAreaLayoutGuide.trailingAnchor),
            accessory.centerXAnchor.constraint(equalTo: container.safeAreaLayoutGuide.centerXAnchor),
            accessory.widthAnchor.constraint(lessThanOrEqualToConstant: 780),
            fullWidth,
            accessory.bottomAnchor.constraint(equalTo: guide.topAnchor),
            controller.visitableView.bottomAnchor.constraint(equalTo: accessory.topAnchor)
        ])
    }
}
