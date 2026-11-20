@preconcurrency import HotwireNative
import ObjectiveC
import UIKit

/// The chat a page turns into in place (docs/server-contract.md, "New chat
/// and New bot"). From path configuration v4, New chat and New bot are pages,
/// and the server draws the question on them the moment it's sent, in the
/// same web view; its redirect to the chat then comes as a visit proposed
/// with the form's response. That visit replaces the screen it was sent
/// from where it stands, never the root under a pushed page, and without a
/// skeleton or a spinner over a page that already shows the question.
///
/// Hotwire Native moves the shared web view into a new screen for the visit
/// and hides it until the response renders. The new screen shows what the
/// old one showed meanwhile (the page and the app's composer, as they were),
/// and lets go of it once the chat's page has rendered and its composer
/// connected: a prototype that let the chat's skeleton cover it hid the
/// question for over a second.
enum NewChatHandOff {
    /// Marks the visit the hand-off routes again, so it's taken as itself.
    nonisolated static let property = "cww_new_chat_hand_off"

    private nonisolated(unsafe) static var key: UInt8 = 0

    /// Never held longer than this, whatever the visit does.
    static var timeout: Duration = .seconds(10)
    /// How long a rendered page waits for its composer to connect.
    static let composerLimit: Duration = .milliseconds(600)
    static let fadeSeconds: TimeInterval = 0.15

    /// Whether a visit proposed to `url` is the chat the page on top just
    /// turned into: proposed from a form's response, to a chat that doesn't
    /// say where from (`from=` drill-downs are pushed), while the screen on
    /// top, whose form it was, shows a page whose composer starts chats.
    nonisolated static func takes(_ url: URL, hasResponse: Bool, onTop top: URL?, submittedFromTop: Bool) -> Bool {
        guard hasResponse, submittedFromTop, case .chat = AppRoute(url: url).kind, !saysWhereFrom(url),
              let top, AppRoute(url: top).startsChats
        else { return false }
        return true
    }

    nonisolated static func saysWhereFrom(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "from" } == true
    }

    /// The same visit, replacing the screen on top where it stands, at once.
    nonisolated static func replacing(_ proposal: VisitProposal) -> VisitProposal {
        var properties = proposal.properties
        properties["context"] = Navigation.Context.default.rawValue
        properties["presentation"] = Navigation.Presentation.replace.rawValue
        properties["animated"] = false
        properties[property] = true
        return VisitProposal(url: proposal.url, options: proposal.options, properties: properties, parameters: proposal.parameters)
    }

    nonisolated static func isHandOff(_ proposal: VisitProposal) -> Bool {
        proposal.properties[property] as? Bool == true
    }

    /// Marks New chat or New bot opened in place.
    nonisolated static let inPlaceProperty = "cww_opens_in_place"

    /// Whether `proposal` is New chat or New bot's sentence page opened from
    /// a page (the bar's New chat, Bots' New bot, a link): the person asked
    /// for it, there's a page under it to go back to, and it isn't a place
    /// (the sidebar's, a shortcut's), which takes the root.
    nonisolated static func opensInPlace(_ proposal: VisitProposal, hasScreens: Bool, presenting: Bool) -> Bool {
        let route = AppRoute(url: proposal.url)
        guard route.kind == .newChat || route.isNewBot, hasScreens, !presenting, proposal.options.response == nil,
              proposal.properties[inPlaceProperty] as? Bool != true, proposal.properties[property] as? Bool != true,
              proposal.properties.context != .modal,
              proposal.properties["presentation"] as? String ?? Navigation.Presentation.default.rawValue == Navigation.Presentation.default.rawValue
        else { return false }
        return true
    }

    /// The same visit pushed without the slide: the screen comes up showing
    /// the page it's opened from (`screen(for:replacing:)`) until its own has
    /// drawn, so it turns in place, and Back still returns there.
    nonisolated static func openingInPlace(_ proposal: VisitProposal) -> VisitProposal {
        var properties = proposal.properties
        properties["animated"] = false
        properties[inPlaceProperty] = true
        return VisitProposal(url: proposal.url, options: proposal.options, properties: properties, parameters: proposal.parameters)
    }

    nonisolated static func isOpeningInPlace(_ proposal: VisitProposal) -> Bool {
        proposal.properties[inPlaceProperty] as? Bool == true
    }

    /// Routes the visit as the hand-off. Hotwire fades every replace (the
    /// app's `animateReplaceActions`); this one swaps the screen unseen.
    static func route(_ proposal: VisitProposal, on navigator: Navigator) {
        let fades = Hotwire.config.animateReplaceActions
        Hotwire.config.animateReplaceActions = false
        defer { Hotwire.config.animateReplaceActions = fades }
        navigator.route(replacing(proposal))
    }

    /// The chat's screen, showing what `leaving` showed until its own page
    /// is up, with no skeleton.
    static func screen(for url: URL, replacing leaving: UIViewController?) -> VisitableViewController {
        let controller = WebScreen.make(url: url, skeleton: false)
        // The page's own title as it turned ("New chat", which Decisions' All clear also takes as it turns), not the
        // leaving screen's bar, which can still say what it was before ("Decisions").
        let turned = (leaving as? VisitableViewController)?.visitableView.webView?.title.flatMap { $0.isEmpty ? nil : $0 }
        controller.navigationItem.title = turned ?? leaving?.navigationItem.title
        // As it's drawn now; a screen not drawn yet has nothing to show but its views.
        guard let leaving, leaving.isViewLoaded,
              let picture = leaving.view.snapshotView(afterScreenUpdates: false) ?? leaving.view.snapshotView(afterScreenUpdates: true)
        else { return controller }

        let size = leaving.view.bounds.size
        picture.translatesAutoresizingMaskIntoConstraints = false
        picture.isUserInteractionEnabled = false
        picture.accessibilityElementsHidden = true
        controller.view.addSubview(picture)
        NSLayoutConstraint.activate([
            picture.topAnchor.constraint(equalTo: controller.view.topAnchor),
            picture.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            picture.widthAnchor.constraint(equalToConstant: size.width),
            picture.heightAnchor.constraint(equalToConstant: size.height)
        ])
        objc_setAssociatedObject(controller, &key, picture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        letGo(of: controller)
        return controller
    }

    /// Whether `controller` still shows the page it replaced.
    static func isHolding(_ controller: UIViewController) -> Bool {
        objc_getAssociatedObject(controller, &key) != nil
    }

    /// Keeps the picture up until the chat's page has rendered (Hotwire shows
    /// the web view again) and its composer has connected, or a moment after.
    private static func letGo(of controller: VisitableViewController) {
        Task { [weak controller] in
            let clock = ContinuousClock()
            let deadline = clock.now + timeout
            var renderedAt: ContinuousClock.Instant?
            while let current = controller, isHolding(current), clock.now < deadline {
                if let webView = current.visitableView.webView, !webView.isHidden {
                    let at = renderedAt ?? clock.now
                    renderedAt = at
                    if !BridgeRegistry.drawsComposer || ComposerController.existing(on: current)?.view.state != nil || clock.now - at > composerLimit { break }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let controller else { return }
            dismiss(on: controller)
        }
    }

    /// Lets the page underneath show: at once when its visit failed, with a
    /// short crossfade onto the same picture otherwise.
    static func dismiss(on controller: UIViewController, animated: Bool = true) {
        guard let picture = objc_getAssociatedObject(controller, &key) as? UIView else { return }
        objc_setAssociatedObject(controller, &key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        guard animated, picture.window != nil else {
            picture.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: fadeSeconds, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            picture.alpha = 0
        } completion: { _ in
            picture.removeFromSuperview()
        }
    }
}
