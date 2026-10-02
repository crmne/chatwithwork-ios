import AuthenticationServices
import HotwireNative
import UIKit

/// `auth-session`: runs a sign-in in the system's secure browser sheet
/// (ASWebAuthenticationSession) instead of the web view.
///
/// Google refuses OAuth inside embedded web views, passkeys and password
/// managers don't work there, and a provider's session in Safari should be
/// reusable. So "Sign in with Google" and connecting a service start here:
/// the server hands the sheet a one-time URL, the flow runs in Safari's
/// context, and the server ends it by redirecting to
/// `chatwithwork://...`, which closes the sheet and comes back to the page.
///
/// Web → native: `start` with `{url, ephemeral?}`, where `url` must be on
/// this app's server; `cancel`. Native → web: a reply to `start` with
/// `{url}` (the callback URL) or `{error}`: `canceled`, `invalid_url`,
/// `unavailable` or `failed`. The handoff URLs are in docs/server-contract.md.
final class AuthSessionComponent: BridgeComponent {
    override nonisolated class var name: String { "auth-session" }

    private var session: ASWebAuthenticationSession?
    private let anchor = PresentationAnchor()

    override func onReceive(message: Message) {
        switch message.event {
        case "start": start(message)
        case "cancel": cancel()
        default: break
        }
    }

    override func onViewDidDisappear() {
        // A sheet with nowhere to report back to would only confuse.
        if destinationViewController?.view.window == nil { cancel() }
    }

    private func start(_ message: Message) {
        guard let request: AuthSessionRequest = message.data() else { return }
        let environment = AppEnvironment.current

        guard let url = request.resolvedURL(in: environment) else {
            finish(.failure("invalid_url"))
            return
        }

        session?.cancel()
        anchor.window = destinationViewController?.view.window

        let session = ASWebAuthenticationSession(
            url: url,
            callback: .customScheme(environment.callbackScheme)
        ) { @Sendable [weak self] callbackURL, error in
            // Called on a queue of the session's choosing.
            let outcome = AuthSessionOutcome(callbackURL: callbackURL, error: error)
            Task { @MainActor in self?.finish(outcome) }
        }
        session.presentationContextProvider = anchor
        session.prefersEphemeralWebBrowserSession = request.ephemeral ?? false
        self.session = session

        if !session.start() {
            finish(.failure("unavailable"))
        }
    }

    private func cancel() {
        session?.cancel()
        session = nil
    }

    private func finish(_ outcome: AuthSessionOutcome) {
        session = nil
        reply(to: "start", with: outcome.reply)
    }
}

nonisolated struct AuthSessionRequest: Decodable, Equatable {
    let url: String
    let ephemeral: Bool?

    /// Only this app's own server may start a session, and only over HTTPS
    /// outside development builds.
    func resolvedURL(in environment: AppEnvironment) -> URL? {
        guard let url = URL(string: url, relativeTo: environment.baseURL)?.absoluteURL,
              environment.owns(url),
              url.scheme == "https" || environment.name == .development
        else { return nil }
        return url
    }
}

nonisolated struct AuthSessionReply: Encodable, Equatable {
    let url: String?
    let error: String?
}

nonisolated enum AuthSessionOutcome: Sendable, Equatable {
    case success(URL)
    case failure(String)

    init(callbackURL: URL?, error: Error?) {
        if let callbackURL {
            self = .success(callbackURL)
        } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            self = .failure("canceled")
        } else {
            self = .failure("failed")
        }
    }

    var reply: AuthSessionReply {
        switch self {
        case .success(let url): AuthSessionReply(url: url.absoluteString, error: nil)
        case .failure(let error): AuthSessionReply(url: nil, error: error)
        }
    }
}

private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    weak var window: UIWindow?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? ASPresentationAnchor()
    }
}
