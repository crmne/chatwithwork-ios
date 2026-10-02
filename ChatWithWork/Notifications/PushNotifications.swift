import UIKit
import UserNotifications

/// Push notifications: permission, the APNs token, and opening the page a
/// notification is about.
///
/// The app never sends the token anywhere itself. A page asks for it through
/// the `notification-token` bridge component and posts it to the server with
/// the person's session (docs/server-contract.md, "Push notifications").
final class PushNotifications: NSObject {
    static let shared = PushNotifications()

    /// Called with the page a tapped notification points to. A notification
    /// tapped before anyone listens waits here until someone does.
    var onOpen: ((URL) -> Void)? {
        didSet {
            if let onOpen, let pendingURL {
                self.pendingURL = nil
                onOpen(pendingURL)
            }
        }
    }

    /// Whether the page a notification points to is on screen right now, in
    /// which case it would only repeat what the person sees.
    var isShowing: ((URL) -> Bool)?

    private var environment = AppEnvironment.current
    private(set) var deviceToken: String?
    private var waitingForToken: [CheckedContinuation<String?, Never>] = []
    /// A notification tapped before the shell was ready to open it.
    private var pendingURL: URL?

    func configure(environment: AppEnvironment) {
        self.environment = environment
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: State and token

    func currentState() async -> PushState {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let token = status.allowsDelivery ? await registeredToken() : nil
        return state(status: status, token: token)
    }

    func requestToken() async -> PushState {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus

        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }

        let token = status.allowsDelivery ? await registeredToken() : nil
        return state(status: status, token: token)
    }

    /// Re-registers on launch and after sign-in, so a token that changed
    /// reaches the server the next time a page asks for it.
    func refreshRegistrationIfAuthorized() {
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status.allowsDelivery {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func registeredToken() async -> String? {
        let token = await withCheckedContinuation { continuation in
            waitingForToken.append(continuation)
            UIApplication.shared.registerForRemoteNotifications()

            // APNs normally answers in well under a second; never leave a
            // page waiting on a device that can't reach it.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.resolveWaiting(with: self?.deviceToken)
            }
        }
        return token
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        resolveWaiting(with: token)
    }

    func didFailToRegister(error: Error) {
        resolveWaiting(with: nil)
    }

    private func resolveWaiting(with token: String?) {
        let waiting = waitingForToken
        waitingForToken.removeAll()
        waiting.forEach { $0.resume(returning: token) }
    }

    private func state(status: UNAuthorizationStatus, token: String?) -> PushState {
        PushState(
            status: status.contractName,
            token: token,
            platform: "ios",
            environment: environment.pushEnvironment.apnsName,
            appId: environment.bundleIdentifier
        )
    }

    // MARK: Opening

    fileprivate func shows(path: String?) -> Bool {
        guard let url = NotificationRoute.url(path: path, environment: environment) else { return false }
        return isShowing?(url) ?? false
    }

    fileprivate func open(path: String?) {
        guard let url = NotificationRoute.url(path: path, environment: environment) else { return }
        if let onOpen {
            onOpen(url)
        } else {
            pendingURL = url
        }
    }
}

extension PushNotifications: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let path = notification.request.content.userInfo["path"] as? String
        let onScreen = await MainActor.run {
            PushNotifications.shared.shows(path: path)
        }
        return onScreen ? [] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let path = response.notification.request.content.userInfo["path"] as? String
        await MainActor.run {
            PushNotifications.shared.open(path: path)
        }
    }
}

/// What `notification-token` replies with.
nonisolated struct PushState: Encodable, Equatable, Sendable {
    let status: String
    let token: String?
    let platform: String
    let environment: String
    let appId: String
}

/// The page a notification points to: its `path` key, on this server.
nonisolated enum NotificationRoute {
    static func url(path: String?, environment: AppEnvironment) -> URL? {
        guard let path, path.hasPrefix("/"), !path.hasPrefix("//") else { return nil }
        let url = environment.url(path: path)
        return environment.owns(url) ? url : nil
    }
}

nonisolated extension UNAuthorizationStatus {
    var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    var contractName: String {
        switch self {
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        case .denied: "denied"
        case .notDetermined: "not_determined"
        @unknown default: "not_determined"
        }
    }
}
