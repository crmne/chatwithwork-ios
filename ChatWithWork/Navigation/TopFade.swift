import UIKit
import WebKit

/// A chat's top edge. The bar has no surface, hairline or button backgrounds,
/// and sits on the page's canvas; what scrolls up fades into that canvas just
/// below the title rather than ending on a line.
///
/// The web view stays below the bar (WebScreen), so offset 0 is the page's
/// start and a page that scrolls to a question, or a pull to refresh, works
/// as on any other screen. The fade covers the web view's top instead of
/// running it under the bar, and the page keeps clear of the fade through
/// `--native-top-bar-height`, the rule the server already has for Android
/// (docs/server-contract.md).
enum TopFade {
    /// How far below the bar the fade reaches, in points.
    static let height: CGFloat = 36

    /// How much of the page the fade covers, in CSS pixels. Together with the
    /// page's own 12 pixels above a chat's first message, it clears the fade.
    /// The fade's last quarter is close to clear, so this holds at the smallest
    /// page zoom too (TextSize).
    static let pageCovered: CGFloat = 24

    /// Set on the document, which Turbo keeps from page to page, as each page
    /// loads. Only a chat's rules read it.
    static var pageScript: WKUserScript {
        WKUserScript(
            source: "document.documentElement.style.setProperty('--native-top-bar-height', '\(Int(pageCovered))px')",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    /// The canvas's opacity down the fade: an ease rather than a ramp, whose
    /// ends would show as lines.
    static let stops: [(location: CGFloat, alpha: CGFloat)] = [(0, 1), (0.25, 0.88), (0.5, 0.55), (0.75, 0.18), (1, 0)]

    static func install(on controller: UIViewController) {
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        bar.titleTextAttributes = [.foregroundColor: Palette.ink]
        controller.navigationItem.standardAppearance = bar
        controller.navigationItem.compactAppearance = bar
        controller.navigationItem.scrollEdgeAppearance = bar
        controller.navigationItem.compactScrollEdgeAppearance = bar
        NavigationBarItems.setBare(on: controller)

        let fade = TopFadeView()
        fade.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(fade)
        NSLayoutConstraint.activate([
            fade.topAnchor.constraint(equalTo: controller.view.topAnchor),
            fade.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            fade.heightAnchor.constraint(equalToConstant: height)
        ])
    }

    /// A web dialog is over the page, and the fade would wash out its top,
    /// so the fade steps aside while the composer does (ComposerState.visible).
    static func setHidden(_ hidden: Bool, on controller: UIViewController) {
        controller.viewIfLoaded?.subviews.first { $0 is TopFadeView }?.isHidden = hidden
    }
}

/// The fade itself: touches and VoiceOver go through it to the page.
final class TopFadeView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        (layer as? CAGradientLayer)?.locations = TopFade.stops.map { NSNumber(value: Double($0.location)) }
        paint()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TopFadeView, _: UITraitCollection) in
            view.paint()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Layers take fixed colors, so this follows the theme by hand.
    private func paint() {
        let canvas = Palette.canvas.resolvedColor(with: traitCollection)
        (layer as? CAGradientLayer)?.colors = TopFade.stops.map { canvas.withAlphaComponent($0.alpha).cgColor }
    }
}
