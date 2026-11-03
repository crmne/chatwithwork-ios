import UIKit

/// Keeps the screen on while dictation records or transcribes, so the phone
/// doesn't lock and stop it halfway (Carmine: "otherwise my phone goes off
/// and I cannot finish transcribing"). It lets go as the app goes to the
/// background or the composer leaves the screen, takes hold again when both
/// come back while it's still wanted, and lets go for good when the
/// composer goes.
@MainActor
final class ScreenAwake {
    /// What keeps the screen on: the app's idle timer, or a stand-in in tests.
    private let keepOn: (Bool) -> Void

    /// Whether dictation wants the screen on.
    var isWanted = false { didSet { apply() } }
    /// Whether the composer is in a window.
    var isOnScreen = true { didSet { apply() } }
    private var isInForeground = true { didSet { apply() } }
    private(set) var isHolding = false
    private var observers: [NSObjectProtocol] = []

    private let center: NotificationCenter

    init(center: NotificationCenter = .default, keepOn: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.center = center
        self.keepOn = keepOn
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isInForeground = false }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isInForeground = true }
            }
        ]
    }

    private func apply() {
        let hold = isWanted && isOnScreen && isInForeground
        guard hold != isHolding else { return }
        isHolding = hold
        keepOn(hold)
    }

    isolated deinit {
        if isHolding { keepOn(false) }
        observers.forEach(center.removeObserver)
    }
}
