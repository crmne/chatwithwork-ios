import HotwireNative
import UIKit

/// `sidebar`: tells the app the person's chat list changed, so the native
/// sidebar fetches it again (docs/server-contract.md, "The sidebar"). Its
/// name in the user agent also tells the server this build draws the
/// sidebar itself: no tabs, New chat in the bar, and services connected in
/// the system browser.
///
/// Web → native: `connect` `{}`, nothing to do; `changed` `{}`, refetch if
/// the sidebar is open, else when it next opens.
final class SidebarComponent: BridgeComponent {
    override nonisolated class var name: String { "sidebar" }

    override func onReceive(message: Message) {
        guard message.event == "changed" else { return }
        SidebarShell.current?.sidebarChanged()
    }
}
