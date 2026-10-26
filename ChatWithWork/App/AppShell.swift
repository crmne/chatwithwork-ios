import HotwireNative
import UIKit

/// Owns the window's root and decides what it shows: the signed-out welcome
/// with its sign-in sheet, or the sidebar shell for one organization.
///
/// The server says when that changes, and the shell listens for it in the
/// navigators' traffic (it is every navigator's delegate):
///
/// - A 401, or any page landing on the sign-in form, means there is no
///   session: show the welcome screen.
/// - `/recede_historical_location` while signed out means sign-in finished:
///   build the sidebar shell from scratch, so nothing keeps a signed-out page.
/// - A link into another organization means the person switched: rebuild the
///   shell inside it, then open the link there.
///
/// See docs/server-contract.md for the server's half.
final class AppShell: NSObject {
    enum State {
        case launching
        case signedIn(SidebarShell)
        case signedOut(SignedOutFlow)
    }

    private(set) var state: State = .launching
    private let window: UIWindow
    private let environment: AppEnvironment
    private let memory: SessionMemory
    private var account: AccountSlug?
    /// A link that arrived while signed out, opened once signed in.
    private var pendingURL: URL?

    init(window: UIWindow, environment: AppEnvironment, memory: SessionMemory = .standard) {
        self.window = window
        self.environment = environment
        self.memory = memory
        super.init()
    }

    func start() {
        if memory.hasSignedIn || LaunchOptions.assumesSignedIn {
            showSignedIn(account: memory.lastAccount, animated: false)
            PushNotifications.shared.refreshRegistrationIfAuthorized()
        } else {
            showSignedOut(reason: .firstLaunch, animated: false)
        }

        PushNotifications.shared.onOpen = { [weak self] url in
            self?.open(url)
        }
        PushNotifications.shared.isShowing = { [weak self] url in
            self?.isShowing(url) ?? false
        }

        if let pendingURL {
            self.pendingURL = nil
            open(pendingURL)
        }
    }

    // MARK: Opening links

    /// Opens a universal link or a notification's page in the right place.
    func open(_ url: URL) {
        guard environment.owns(url) else {
            UIApplication.shared.open(url)
            return
        }

        switch state {
        case .launching:
            pendingURL = url
        case .signedOut(let flow):
            if AppRoute(url: url).isAuthentication {
                flow.route(url)
            } else {
                pendingURL = url
                flow.presentSignIn()
            }
        case .signedIn(let shell):
            route(url, in: shell)
        }
    }

    /// The app's own links (`AppLink`): `chatwithwork://open?path=...` opens a
    /// page of this server, and `chatwithwork://new-chat` a new chat, which
    /// starts listening (`dictate=1`), gets what was shared into its
    /// composer (`title`, `text`, `url`), and takes the shared files the
    /// share extension left in the app group (`shared`). Sign-in and
    /// hand-off callbacks belong to the browser sheet and are ignored here.
    func openAppLink(_ url: URL, attempt: Int = 0) {
        guard url.scheme == AppLink.scheme else { return }
        // Launched by the link: let the shell put up its first screen first.
        if case .signedIn(let shell) = state, shell.navigator.rootViewController.viewControllers.isEmpty, attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.openAppLink(url, attempt: attempt + 1) }
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first(where: { $0.name == name })?.value }

        switch url.host() {
        case "open":
            guard let path = value("path"), path.hasPrefix("/"), !path.hasPrefix("//") else { return }
            open(environment.url(path: path))
        case "new-chat":
            if value("dictate") == "1" { ComposerController.dictatesOnConnect = true }
            if let shared = value("shared") {
                ComposerController.pendingFiles = SharedInbox.take(shared).map { ComposerFile(name: $0.name, type: $0.type, bytes: $0.data) }
            }
            // The words wait in the native composer too, whatever the page does with them.
            // Joined as the server joins them for `/chats/new`, so a composer it filled is recognized.
            var shared: [String] = []
            for word in ["title", "text", "url"].compactMap(value).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !word.isEmpty && !shared.contains(word) {
                shared.append(word)
            }
            let sharedText = shared.joined(separator: "\n\n")
            if !sharedText.isEmpty { ComposerController.pendingText = sharedText }
            // A new chat already on screen takes them as they are.
            if case .signedIn(let shell) = state, let composer = ComposerController.onNewChat(shell.navigator.rootViewController) {
                shell.setOpen(false, animated: false)
                composer.takePending()
                return
            }
            var components = URLComponents()
            components.path = AppPath.path(AppPath.newChat, in: account ?? currentAccount)
            // Percent-encoded by hand: URLComponents leaves "+" alone, which the server reads as a space.
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "+&=")
            let prefill = ["title", "text", "url"].compactMap { name in
                value(name).flatMap { $0.addingPercentEncoding(withAllowedCharacters: allowed) }.map { URLQueryItem(name: name, value: $0) }
            }
            components.percentEncodedQueryItems = prefill.isEmpty ? nil : prefill
            open(environment.url(path: components.string ?? AppPath.newChat))
        default:
            break
        }
    }

    /// The organization the shell shows, read from its page when it started unprefixed.
    private var currentAccount: AccountSlug? {
        guard case .signedIn(let shell) = state, let url = shell.navigator.session.webView.url else { return nil }
        return AppRoute(url: url).account
    }

    private func route(_ url: URL, in shell: SidebarShell) {
        let route = AppRoute(url: url)

        if let target = route.account, target != account {
            switchAccount(to: target, continuingTo: url)
            return
        }

        shell.setOpen(false, animated: false)
        if route.kind == .newChat, url.query() == nil {
            shell.startNewChat()
        } else {
            shell.navigator.route(url)
        }
    }

    /// Whether the screen on top shows `url`'s page.
    private func isShowing(_ url: URL) -> Bool {
        guard case .signedIn(let shell) = state, let current = shell.navigator.activeWebView.url else { return false }
        return AppRoute(url: current).path == AppRoute(url: url).path
    }

    // MARK: Signed in

    private func showSignedIn(account: AccountSlug?, continuingTo url: URL? = nil, animated: Bool = true) {
        let shell = SidebarShell(environment: environment, account: account, navigatorDelegate: self, memory: memory)
        self.account = account
        state = .signedIn(shell)

        // In the window before the first page loads, so the page starts under
        // the bars at their real height.
        replaceRoot(with: shell, animated: animated)
        shell.start()

        if let url {
            route(url, in: shell)
        }
    }

    private func didSignIn(continuingTo url: URL? = nil) {
        // Several signals can report the same sign-in.
        guard case .signedOut = state else { return }

        memory.hasSignedIn = true
        let next = pendingURL ?? url
        pendingURL = nil
        // Without a link into an organization, the shell starts unprefixed and
        // the server picks the organization this person used last.
        let target = next.map(AppRoute.init(url:))
        showSignedIn(account: target?.account, continuingTo: next.flatMap { opensOnTop(of: $0) ? $0 : nil })
        PushNotifications.shared.refreshRegistrationIfAuthorized()
    }

    private func switchAccount(to target: AccountSlug, continuingTo url: URL) {
        guard target != account else { return }
        memory.lastAccount = target
        showSignedIn(account: target, continuingTo: opensOnTop(of: url) ? url : nil)
    }

    /// The new chat page isn't opened again after a rebuild: the shell starts
    /// on it (in the list last chosen there), and it's what an organization
    /// switcher links to. Nor is the chat list, which the sidebar replaced.
    private func opensOnTop(of url: URL) -> Bool {
        switch AppRoute(url: url).kind {
        case .newChat, .list(.chats), .authentication, .historicalLocation: false
        default: true
        }
    }

    // MARK: Signed out

    enum SignOutReason {
        case firstLaunch
        /// The person logged out.
        case signedOut
        /// The server stopped recognizing the session.
        case sessionExpired
    }

    private func showSignedOut(reason: SignOutReason, animated: Bool = true) {
        // Every tab can report the same expired session.
        if case .signedOut = state { return }

        memory.hasSignedIn = false
        memory.lastAccount = nil
        account = nil
        PushNotifications.shared.forgetKey()

        let flow = SignedOutFlow(environment: environment, navigatorDelegate: self)
        flow.onLocationChange = { [weak self] url in
            guard let self, self.signsIn(AppRoute(url: url)) else { return }
            self.later { $0.didSignIn(continuingTo: url) }
        }
        state = .signedOut(flow)
        replaceRoot(with: flow.rootViewController, animated: animated)

        if reason == .sessionExpired {
            // Let the cross-fade settle before the sheet slides up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak flow] in
                flow?.presentSignIn()
            }
        }
    }

    // MARK: Root

    private func replaceRoot(with viewController: UIViewController, animated: Bool) {
        let previous = window.rootViewController
        guard previous !== viewController else { return }

        let swap = { [window] in
            previous?.presentedViewController?.dismiss(animated: false)
            window.rootViewController = viewController
        }

        if animated, previous != nil {
            UIView.transition(with: window, duration: 0.35, options: [.transitionCrossDissolve, .allowAnimatedContent], animations: swap)
        } else {
            swap()
        }
    }

    // MARK: Notices

    /// `recede_or_redirect_to(url, notice: "...")` puts the notice on the
    /// historical location it sends the app to; show it the native way.
    private func showNotice(in url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let notice = items.first(where: { $0.name == "notice" })?.value, !notice.isEmpty {
            ToastCenter.shared.show(notice, style: .notice)
        } else if let alert = items.first(where: { $0.name == "alert" })?.value, !alert.isEmpty {
            ToastCenter.shared.show(alert, style: .alert)
        }
    }
}

// MARK: - NavigatorDelegate

extension AppShell: NavigatorDelegate {
    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        let route = AppRoute(url: proposal.url)

        if case .historicalLocation(let location) = route.kind {
            showNotice(in: proposal.url)
            if case .signedOut = state {
                later { $0.didSignIn() }
                return .reject
            }
            // Going back from the one chat screen, with nothing over it
            // (deleting it, on a server that still recedes): there's nothing
            // under it, so a new chat takes its place rather than leaving
            // the deleted one up.
            if location == .recede, case .signedIn(let shell) = state {
                let main = shell.navigator.rootViewController
                if main.viewControllers.count <= 1, main.presentedViewController == nil {
                    later { _ in shell.startNewChat() }
                    return .reject
                }
            }
            return .accept
        }

        switch state {
        case .launching:
            return .accept

        case .signedOut:
            // Leaving the sign-in pages for a page inside the app means the
            // server signed someone in, even if it didn't recede.
            if signsIn(route) {
                later { $0.didSignIn(continuingTo: proposal.url) }
                return .reject
            }
            return .accept

        case .signedIn(let shell):
            if route.isSignIn {
                // A redirect here follows a form, which is how logging out
                // ends; anything else means the session ran out.
                let reason: SignOutReason = proposal.isRedirect ? .signedOut : .sessionExpired
                later { $0.showSignedOut(reason: reason) }
                return .reject
            }

            if let target = route.account, let account, target != account {
                later { $0.switchAccount(to: target, continuingTo: proposal.url) }
                return .reject
            }

            shell.noteVisit(proposal.url)
            return .accept
        }
    }

    /// Changes to the window's root wait for the navigation callback that
    /// asked for them to finish, so no navigator is torn down mid-call.
    private func later(_ change: @escaping (AppShell) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            change(self)
        }
    }

    func visitableDidFailRequest(_ visitable: Visitable, error: HotwireNativeError, retryHandler: RetryBlock?) {
        if error.statusCode == 401 {
            switch state {
            case .signedIn:
                later { $0.showSignedOut(reason: .sessionExpired) }
            case .signedOut(let flow):
                later { _ in flow.presentSignIn() }
            case .launching:
                break
            }
            return
        }

        visitable.visitableViewController.presentError(error, retryHandler: retryHandler)
    }

    func requestDidFinish(at url: URL) {
        switch state {
        case .signedIn(let shell):
            // Servers that redirect a signed-out request to the sign-in form
            // instead of answering 401 still land here.
            let locations = [shell.navigator.session.webView.url, shell.navigator.modalSession.webView.url].compactMap { $0 }
            if locations.contains(where: { AppRoute(url: $0).isSignIn }) {
                later { $0.showSignedOut(reason: .sessionExpired) }
                return
            }

            if account == nil, let current = shell.navigator.session.webView.url, let slug = AppRoute(url: current).account {
                // Started unprefixed: the server picked the organization.
                account = slug
                memory.lastAccount = slug
                shell.store.account = slug
                shell.sidebarChanged()
            }
            if let current = shell.navigator.session.webView.url { shell.noteVisit(current) }

        case .signedOut(let flow):
            if let location = flow.navigator.modalSession.webView.url, signsIn(AppRoute(url: location)) {
                later { $0.didSignIn(continuingTo: location) }
            }

        case .launching:
            break
        }
    }

    /// Whether reaching `route` while signed out means a session now exists.
    private func signsIn(_ route: AppRoute) -> Bool {
        if route.account != nil { return true }
        switch route.kind {
        case .list, .newChat, .chat, .historicalLocation(.recede): return true
        default: return route.path == "/accounts"
        }
    }
}
