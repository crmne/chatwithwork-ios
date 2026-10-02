import HotwireNative
import UIKit

/// `toast`: a short native notice at the top of the screen.
///
/// Web → native: `show` with `{message, type?}`, where type is `notice`
/// (default), `info`, `alert` or `error`, the kinds of Rails flash. Joe
/// Masilotti's contract plus `type`. The web sends flash messages through it
/// instead of showing its own.
final class NativeToastComponent: BridgeComponent {
    override nonisolated class var name: String { "toast" }

    override func onReceive(message: Message) {
        guard message.event == "show", let data: ToastData = message.data() else { return }
        ToastCenter.shared.show(data.message, style: ToastStyle(type: data.type))
    }
}

nonisolated struct ToastData: Decodable, Equatable {
    let message: String
    let type: String?
}

/// `haptic`: taptic feedback for something that just happened on the page.
///
/// Web → native: `vibrate` with `{feedback}`: `success`, `warning` and
/// `error` (Joe Masilotti's), plus `selection`, `light`, `medium`, `heavy`,
/// `soft` and `rigid`. Unknown values fall back to success, as in his.
final class HapticFeedbackComponent: BridgeComponent {
    override nonisolated class var name: String { "haptic" }

    override func onReceive(message: Message) {
        guard message.event == "vibrate", let data: HapticData = message.data() else { return }
        Haptics.play(Haptics.Feedback(rawValue: data.feedback) ?? .success)
    }
}

nonisolated struct HapticData: Decodable, Equatable {
    let feedback: String
}

enum Haptics {
    enum Feedback: String, CaseIterable, Sendable {
        case success, warning, error
        case selection
        case light, medium, heavy, soft, rigid
    }

    static func play(_ feedback: Feedback) {
        switch feedback {
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .soft: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .rigid: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }
}
