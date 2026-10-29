import UIKit

/// Decisions in the chat screen's bar, beside the sidebar button, as the web
/// draws it in its top bar: the list-checks icon and how many decisions
/// wait for the person, on the attention wash, or the icon alone when none
/// do. It opens the Decisions page (`waiting.url`).
final class DecisionsPill: UIButton {
    private(set) var count = 0

    convenience init(action: @escaping () -> Void) {
        self.init(configuration: .plain(), primaryAction: UIAction { _ in action() })
        accessibilityIdentifier = "shell.decisions"
        accessibilityLabel = String(localized: "Decisions")
        update(count: 0)
    }

    func update(count: Int) {
        self.count = count
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "checklist", withConfiguration: UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium).applying(UIImage.SymbolConfiguration(weight: .semibold)))
        configuration.imagePadding = 5
        configuration.cornerStyle = .capsule
        if count > 0 {
            var title = AttributedString("\(count)")
            title.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
            configuration.attributedTitle = title
            configuration.baseForegroundColor = Palette.attentionInk
            configuration.background.backgroundColor = Palette.attention.withAlphaComponent(0.16)
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 11)
        } else {
            configuration.baseForegroundColor = Palette.ink
            configuration.background.backgroundColor = .clear
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 6)
        }
        self.configuration = configuration
        accessibilityValue = count == 0 ? String(localized: "None waiting") : count == 1 ? String(localized: "1 waiting") : String(localized: "\(count) waiting")
        invalidateIntrinsicContentSize()
        sizeToFit()
    }
}
