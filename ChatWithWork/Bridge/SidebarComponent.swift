import HotwireNative
import UIKit

/// `sidebar`: tells the app the person's chat list changed, so the native
/// sidebar fetches it again (docs/server-contract.md, "The sidebar"). Its
/// name in the user agent also tells the server this build draws the
/// sidebar itself: no tabs, New chat in the bar, and services connected in
/// the system browser.
///
/// Web → native: `connect` `{}`, which the app answers to send a chat's
/// action from the sidebar; `changed` `{}`, refetch if the sidebar is open,
/// else when it next opens. Native → web: a reply to `connect`,
/// `{action: "perform", url, method, confirm?, destructive?}`, which the
/// page sends like the web row's menu would.
final class SidebarComponent: BridgeComponent {
    override nonisolated class var name: String { "sidebar" }

    /// Every page's component that connected, to answer the one on screen.
    private static let connected = NSHashTable<SidebarComponent>.weakObjects()

    override func onReceive(message: Message) {
        switch message.event {
        case "connect":
            Self.connected.add(self)
        case "changed":
            SidebarShell.current?.sidebarChanged()
        default:
            break
        }
    }

    /// Hands a chat's action to the page showing in `screen`, or, failing
    /// that, to any page still connected. False when no page can send it.
    @discardableResult
    static func perform(_ action: SidebarData.Action, on screen: UIViewController?) -> Bool {
        let components = connected.allObjects
        guard let component = components.first(where: { $0.destinationViewController === screen }) ?? components.last else { return false }
        let data = Perform(url: action.url, method: action.method, confirm: action.confirm, destructive: action.destructive)
        Task { _ = try? await component.reply(to: "connect", with: data) }
        return true
    }

    private struct Perform: Encodable {
        let action = "perform"
        let url: String
        let method: String
        let confirm: String?
        let destructive: Bool?
    }
}
