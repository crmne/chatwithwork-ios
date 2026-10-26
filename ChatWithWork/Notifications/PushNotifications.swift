import UIKit
import UserNotifications

/// Push notifications: permission, the APNs token, and opening the page a
/// notification is about.
///
/// The app never sends the token anywhere itself. A page asks for it through
/// the `notification-token` bridge component and posts it to the server with
/// the person's session (docs/server-contract.md, "Push notifications").
///
/// The app offers once, when a page says the moment has come (a change
/// waiting for approval, an answer that takes a while), with a short
/// explanation before iOS's own prompt. When the person allows
/// notifications, every `notification-token` on screen hears the new state,
/// so the page registers the token without waiting for another page.
///
/// The registration's answer is the phone's notification key, which the
/// page hands back (`key`) and the app keeps in the keychain group it shares
/// with its notification service extension, which fetches each
/// notification's words with it (`NotificationWords`). Until it has one for
/// the current token, the app says `needsKey`, and the page registers at once.
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
    private var defaults = UserDefaults.standard
    /// The components on screen, told when the state changes.
    private let listeners = NSHashTable<AnyObject>.weakObjects()
    private var isAsking = false
    private(set) var deviceToken: String?
    private var waitingForToken: [CheckedContinuation<String?, Never>] = []
    /// A notification tapped before the shell was ready to open it.
    private var pendingURL: URL?

    func configure(environment: AppEnvironment, defaults: UserDefaults = .standard) {
        self.environment = environment
        self.defaults = defaults
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories(Self.categories)
    }

    /// One category per kind the server sends (its `category`), each with
    /// what a notification says when the person hides previews: what
    /// happened, never the chat's title or words.
    static var categories: Set<UNNotificationCategory> {
        let placeholders = [
            "answered": String(localized: "Your answer is ready."),
            "approval_waiting": String(localized: "A change is waiting for your approval."),
            "input_requested": String(localized: "A question is waiting for your answer."),
            "handed_off": String(localized: "A bot handed a conversation to your team."),
            "failed": String(localized: "A chat couldn't finish its answer."),
            "decisions_waiting": String(localized: "Decisions are waiting for you.")
        ]
        return Set(placeholders.map { kind, placeholder in
            UNNotificationCategory(identifier: kind, actions: [], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: placeholder, options: [])
        })
    }

    // MARK: Notification key

    /// Keeps the key the server issued for `token`, on this server, for the
    /// notification service extension.
    func keep(key: String, for token: String) {
        guard !key.isEmpty, !token.isEmpty else { return }
        NotificationKey.save(NotificationKey.Stored(key: key, token: token, baseURL: environment.baseURL))
    }

    /// Whether the app has no key for `token` on this server yet.
    func needsKey(for token: String?) -> Bool {
        guard let token else { return false }
        let stored = NotificationKey.load()
        return stored?.token != token || stored?.baseURL != environment.baseURL
    }

    /// Signing out ends the key's use: the server deleted the registration,
    /// and the next person on this phone gets one of their own.
    func forgetKey() {
        NotificationKey.delete()
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
        let allowedBefore = status.allowsDelivery

        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }

        let token = status.allowsDelivery ? await registeredToken() : nil
        let state = state(status: status, token: token)
        if status.allowsDelivery, !allowedBefore { tellListeners(state) }
        return state
    }

    // MARK: Offering once

    private static let askedKey = "CWWAskedForNotifications"

    /// Whether the app already offered to turn notifications on, on this
    /// install. It offers once: afterwards the Settings row does it.
    var hasAsked: Bool {
        get { defaults.bool(forKey: Self.askedKey) }
        set { defaults.set(newValue, forKey: Self.askedKey) }
    }

    /// Offers to turn notifications on at the moment a page says they'd help
    /// (`notification-token`'s `offer`): the first time a change waits for the
    /// person, or an answer takes a while. A short explanation, then iOS's
    /// prompt if they continue. Offers once per install, and never once iOS
    /// has an answer; either way it returns the state as `get` would.
    func offer(_ reason: NotificationPrompt.Reason, over presenter: @escaping () -> UIViewController?) async -> PushState {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard LaunchOptions.asksForNotifications, !hasAsked, !isAsking, status == .notDetermined,
              let viewController = presenter(), viewController.viewIfLoaded?.window != nil
        else {
            if status != .notDetermined { hasAsked = true }
            return await currentState()
        }

        isAsking = true
        defer { isAsking = false }
        hasAsked = true
        if await NotificationPrompt.confirm(reason, over: viewController) {
            return await requestToken()
        }
        return await currentState()
    }

    // MARK: Listeners

    func addListener(_ listener: PushStateListener) {
        listeners.add(listener)
    }

    private func tellListeners(_ state: PushState) {
        for case let listener as PushStateListener in listeners.allObjects {
            listener.pushStateDidChange(state)
        }
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
            appId: environment.bundleIdentifier,
            needsKey: needsKey(for: token)
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
    // The completion handler variants, not the async ones: Swift runs an
    // async delegate method off the main thread and calls UIKit's completion
    // handler from there, and the handler for a tapped notification touches
    // UIKit, which crashed the app on every tap (build 100). iOS calls these
    // on the main thread; they answer on it whatever thread they're called on.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        let path = notification.request.content.userInfo["path"] as? String
        PushNotifications.onMain {
            let onScreen = PushNotifications.shared.shows(path: path)
            completionHandler(onScreen ? [] : [.banner, .list, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let path = response.notification.request.content.userInfo["path"] as? String
        PushNotifications.onMain {
            PushNotifications.shared.open(path: path)
            completionHandler()
        }
    }

    /// Runs `work` on the main actor: right away when already there (iOS
    /// calls the delegate on the main thread), else on the main queue.
    nonisolated static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async { work() }
        }
    }
}

/// Something on screen that shows or registers the push state.
protocol PushStateListener: AnyObject {
    func pushStateDidChange(_ state: PushState)
}

/// The explanation before iOS's own permission prompt, worded for the
/// moment that brought it up.
enum NotificationPrompt {
    nonisolated enum Reason: String, Decodable, Sendable {
        /// A change or a question waits for the person.
        case approval
        /// An answer is still working after a while.
        case answer
    }

    static let title = String(localized: "Want a nudge when it's ready?")

    static func message(for reason: Reason) -> String {
        switch reason {
        case .approval:
            String(localized: "Chat with Work can tell you when a change waits for your approval, so you can leave the app while it works.")
        case .answer:
            String(localized: "Chat with Work can tell you when an answer is ready, so you can leave the app while it works.")
        }
    }

    /// Whether the person chose to continue to iOS's prompt.
    static func confirm(_ reason: Reason, over viewController: UIViewController) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message(for: reason), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Not now"), style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            let allow = UIAlertAction(title: String(localized: "Continue"), style: .default) { _ in
                continuation.resume(returning: true)
            }
            alert.addAction(allow)
            alert.preferredAction = allow
            viewController.present(alert, animated: true)
        }
    }
}

/// What `notification-token` replies with. `needsKey`: the app has a token
/// but no notification key for it, so the page registers it at once.
nonisolated struct PushState: Encodable, Equatable, Sendable {
    let status: String
    let token: String?
    let platform: String
    let environment: String
    let appId: String
    var needsKey = false
}

/// What the page hands back after registering the token (`key`).
nonisolated struct NotificationKeyData: Decodable, Equatable {
    let key: String
    let token: String
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
