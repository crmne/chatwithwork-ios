import HotwireNative
import UIKit

/// `notification-token`: lets a page turn on push notifications for this
/// device and hand the token to the server, which it posts with the page's
/// own session and CSRF token.
///
/// Web → native:
/// - `connect`: replies with the current state, never asking the person.
/// - `get`: asks for permission if iOS hasn't asked yet, registers with
///   APNs, and replies with the token.
/// - `openSettings`: opens this app's page in iOS Settings, for someone who
///   turned notifications off there.
///
/// Native → web, for `connect` and `get`: `{status, token?, platform,
/// environment, appId}`. `status` is `authorized`, `provisional`,
/// `ephemeral`, `denied` or `not_determined`; `environment` is the APNs
/// gateway (`sandbox` or `production`); `appId` the bundle identifier the
/// server sends to (the APNs topic).
final class NotificationTokenComponent: BridgeComponent {
    override nonisolated class var name: String { "notification-token" }

    override func onReceive(message: Message) {
        switch message.event {
        case "connect":
            Task { [weak self] in
                let state = await PushNotifications.shared.currentState()
                _ = try? await self?.reply(to: "connect", with: state)
            }
        case "get":
            Task { [weak self] in
                let state = await PushNotifications.shared.requestToken()
                _ = try? await self?.reply(to: "get", with: state)
            }
        case "openSettings":
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }
}
