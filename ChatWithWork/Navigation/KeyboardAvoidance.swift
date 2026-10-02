import HotwireNative
import UIKit

/// Keeps web pages above the keyboard by resizing the web view rather than
/// letting WebKit scroll the page under the navigation bar. The composer is
/// docked to the bottom of the viewport, so it rides on top of the keyboard
/// and the conversation above it keeps its full height.
enum KeyboardAvoidance {
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
        visitableView.bottomAnchor.constraint(equalTo: guide.topAnchor).isActive = true
    }
}
