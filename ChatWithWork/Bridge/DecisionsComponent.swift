import HotwireNative
import UIKit

/// `decisions`: Decisions at the end of the bar (docs/server-contract.md,
/// "Decisions in the bar"). On every page but Decisions the bar's last
/// button is Decisions, in the attention tint with a count while some wait;
/// on Decisions it's New chat. Builds without it, and servers that don't
/// render it, keep New chat there.
///
/// Web → native: `connect` `{waiting, here, url}`, then `count` `{waiting}`
/// whenever it changes. Native → web: nothing.
final class DecisionsComponent: BridgeComponent {
    override nonisolated class var name: String { "decisions" }

    override func onReceive(message: Message) {
        switch message.event {
        case "connect":
            guard let data: DecisionsData = message.data(), let url = URL(string: data.url) else { return }
            DecisionsButton.update(DecisionsButton.State(waiting: data.waiting, url: url))
        case "count":
            guard let data: DecisionsCount = message.data(), var state = DecisionsButton.current else { return }
            state.waiting = data.waiting
            DecisionsButton.update(state)
        default:
            break
        }
    }
}

nonisolated struct DecisionsData: Decodable, Equatable, Sendable {
    let waiting: Int
    let here: Bool
    let url: String

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        waiting = max(0, try values.decodeIfPresent(Int.self, forKey: .waiting) ?? 0)
        here = try values.decodeIfPresent(Bool.self, forKey: .here) ?? false
        url = try values.decode(String.self, forKey: .url)
    }

    private enum CodingKeys: String, CodingKey { case waiting, here, url }
}

nonisolated struct DecisionsCount: Decodable, Equatable, Sendable {
    let waiting: Int
}

/// The bar's Decisions button on a main-stack screen, where the shell's New
/// chat would be: the outermost trailing button, any of the page's own (a
/// chat's panel, its menu, a bot's Setup) standing before it.
@MainActor
enum DecisionsButton {
    /// How many wait for the person in this organization, and where
    /// Decisions is: the same for every screen, whichever page said it last.
    /// Whether a screen is Decisions comes from its own address, since a
    /// page's message can arrive while the screen it's for is still being
    /// put up in place of the last one.
    struct State: Equatable {
        var waiting: Int
        var url: URL
    }

    private(set) static var current: State?

    static func update(_ state: State) {
        guard state != current else { return }
        current = state
        SidebarShell.current?.decorateTrailingOnEveryScreen()
    }

    /// Forgets it with the organization's shell.
    static func reset() {
        current = nil
    }

    /// Whether `screen` shows Decisions (or the home, which lands there).
    static func isDecisions(_ screen: UIViewController, decisions: URL) -> Bool {
        guard let url = screen.routedURL else { return false }
        return [AppRoute(url: decisions).path, AppPath.home].contains(AppRoute(url: url).path)
    }

    /// The badge's words: the count, "9+" past nine, none at zero.
    nonisolated static func badge(for waiting: Int) -> String? {
        waiting <= 0 ? nil : waiting > 9 ? "9+" : String(waiting)
    }

    nonisolated static func accessibilityLabel(for waiting: Int) -> String {
        waiting <= 0 ? String(localized: "Decisions") : String(localized: "Decisions, \(waiting) waiting")
    }

    static func item(waiting: Int, action: @escaping () -> Void) -> UIBarButtonItem {
        let image = UIImage(systemName: "signpost.right")
        let item: UIBarButtonItem
        if #available(iOS 26.0, *) {
            item = UIBarButtonItem(image: image, primaryAction: UIAction { _ in action() })
            // Its own glass, apart from the page's buttons beside it, or the
            // group's badge sits on the first of them.
            item.sharesBackground = false
            if let text = badge(for: waiting) {
                var badge = UIBarButtonItem.Badge.string(text)
                badge.backgroundColor = Palette.attention
                badge.foregroundColor = Palette.onAttention
                item.badge = badge
            }
        } else {
            item = UIBarButtonItem(customView: BadgedButton(image: image, badge: badge(for: waiting), action: action))
        }
        item.tintColor = waiting > 0 ? Palette.attentionInk : nil
        item.accessibilityLabel = accessibilityLabel(for: waiting)
        item.accessibilityIdentifier = "shell.decisions"
        return item
    }

}

/// Before iOS 26's bar badges: the symbol with a small count at its top right.
private final class BadgedButton: UIButton {
    init(image: UIImage?, badge: String?, action: @escaping () -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
        setImage(image, for: .normal)
        addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        guard let badge else { return }
        let label = UILabel()
        label.text = badge
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Palette.onAttention
        label.backgroundColor = Palette.attention
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.isAccessibilityElement = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.heightAnchor.constraint(equalToConstant: 16),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            label.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: topAnchor, constant: 6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
