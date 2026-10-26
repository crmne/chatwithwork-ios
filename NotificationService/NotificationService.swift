import UserNotifications

/// Shows a push with the chat's words, fetched from the server as it
/// arrives: the chat's title, what waits as a subtitle, and the start of the
/// answer or what's to decide. The push itself carries only the
/// organization's name, what happened, and `notification_id` (pushes that
/// carry one say `mutable-content`), so those words never pass through
/// Apple's push service. Without the phone's notification key, or when the
/// server doesn't answer in time, it shows the push as it came.
///
/// iOS hides all of it when the person turned previews off, showing the
/// category's placeholder instead (PushNotifications.categories).
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var arrived: UNNotificationContent?
    private var fetching: Task<Void, Never>?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        lock.withLock {
            self.contentHandler = contentHandler
            arrived = request.content
        }

        guard let id = request.content.userInfo["notification_id"] as? String, let key = NotificationKey.load() else {
            return deliver(request.content)
        }

        // A notification's content never changes once made.
        nonisolated(unsafe) let content = request.content
        let fetching = Task { [weak self] in
            let text = await NotificationWords.fetch(id, with: key)
            self?.deliver(text.map { NotificationWords.content(content, saying: $0) } ?? content)
        }
        lock.withLock { self.fetching = fetching }
    }

    /// iOS is about to show the push without waiting longer: as it came.
    override func serviceExtensionTimeWillExpire() {
        let (fetching, arrived) = lock.withLock { (self.fetching, self.arrived) }
        fetching?.cancel()
        if let arrived { deliver(arrived) }
    }

    /// Hands iOS the notification once, whichever comes first.
    private func deliver(_ content: UNNotificationContent) {
        let handler = lock.withLock {
            defer { contentHandler = nil }
            return contentHandler
        }
        handler?(content)
    }
}
