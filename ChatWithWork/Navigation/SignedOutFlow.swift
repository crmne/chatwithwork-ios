import HotwireNative
import SwiftUI
import UIKit
import WebKit

/// What someone without a session sees: a native welcome screen, with the
/// server's sign-in and sign-up pages as sheets over it.
///
/// The sheets come from a navigator of their own whose main stack holds only
/// the welcome screen, so dismissing a sheet always lands somewhere sensible.
final class SignedOutFlow {
    let navigator: Navigator
    private let environment: AppEnvironment
    private var observations: [NSKeyValueObservation] = []

    var rootViewController: UINavigationController { navigator.rootViewController }

    /// Where the sign-in sheet's page is now. The sign-in forms post outside
    /// Turbo, so the page their redirect lands on (the recede after signing
    /// in) reaches the app only as the web view's new URL.
    var onLocationChange: ((URL) -> Void)?

    init(environment: AppEnvironment, navigatorDelegate: NavigatorDelegate) {
        self.environment = environment
        navigator = Navigator(
            configuration: .init(name: "signed-out", startLocation: environment.url(path: Path.signIn)),
            delegate: navigatorDelegate
        )

        let welcome = UIHostingController(rootView: WelcomeView(
            host: environment.isProduction ? nil : environment.baseURL.host(),
            onSignIn: { [weak self] in self?.presentSignIn() },
            onSignUp: { [weak self] in self?.presentSignUp() }
        ))
        welcome.view.backgroundColor = Palette.canvas

        rootViewController.setViewControllers([welcome], animated: false)
        rootViewController.setNavigationBarHidden(true, animated: false)

        observations.append(navigator.modalSession.webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self, let url = webView.url else { return }
                self.onLocationChange?(url)
            }
        })
    }

    func presentSignIn() {
        guard rootViewController.presentedViewController == nil else { return }
        navigator.route(environment.url(path: Path.signIn))
    }

    func presentSignUp() {
        guard rootViewController.presentedViewController == nil else { return }
        navigator.route(environment.url(path: Path.signUp))
    }

    /// Password resets and email confirmations, from a link in an email.
    func route(_ url: URL) {
        navigator.route(url)
    }

    private enum Path {
        static let signIn = "/users/sign_in"
        static let signUp = "/users/sign_up"
    }
}
