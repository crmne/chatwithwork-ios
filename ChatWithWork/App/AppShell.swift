import HotwireNative
import UIKit

/// Owns the window's root and decides what it shows: the signed-out welcome
/// with its sign-in sheet, or the tab shell for one organization.
///
/// The server says when that changes, and the shell listens for it in the
/// navigators' traffic (it is every navigator's delegate):
///
/// - A 401, or any page landing on the sign-in form, means there is no
///   session: show the welcome screen.
/// - `/recede_historical_location` while signed out means sign-in finished:
///   build the tab shell from scratch, so no tab keeps a signed-out page.
/// - A link into another organization means the person switched: rebuild the
///   shell inside it, then open the link there.
///
/// See docs/server-contract.md for the server's half.
final class AppShell: NSObject {
    enum State {
        case launching
        case signedIn(MainTabBarController)
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
            showSignedIn(account: memory.lastAccount, selecting: LaunchOptions.startTab ?? .chats, animated: false)
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
        case .signedIn(let tabs):
            route(url, in: tabs)
        }
    }

    private func route(_ url: URL, in tabs: MainTabBarController) {
        let route = AppRoute(url: url)

        if let target = route.account, target != account {
            switchAccount(to: target, continuingTo: url)
            return
        }

        let tab = route.preferredTab ?? tabs.selectedAppTab
        tabs.select(tab)

        switch route.kind {
        case .tabRoot:
            tabs.select(tab, popToRoot: true)
        case .newChat:
            startNewChat(in: tabs)
        default:
            tabs.navigator(for: tab)?.route(url)
        }
    }

    /// Whether the selected tab's top screen shows `url`'s page.
    private func isShowing(_ url: URL) -> Bool {
        guard case .signedIn(let tabs) = state,
              let current = tabs.navigator(for: tabs.selectedAppTab)?.activeWebView.url
        else { return false }
        return AppRoute(url: current).path == AppRoute(url: url).path
    }

    // MARK: Signed in

    private func showSignedIn(account: AccountSlug?, selecting tab: AppTab = .chats, continuingTo url: URL? = nil, animated: Bool = true) {
        let tabs = MainTabBarController(environment: environment, account: account, navigatorDelegate: self)
        tabs.onNewChat = { [weak self, weak tabs] in
            guard let self, let tabs else { return }
            self.startNewChat(in: tabs)
        }
        self.account = account
        state = .signedIn(tabs)

        // In the window before the first page loads, so the page starts under
        // the bars at their real height.
        replaceRoot(with: tabs, animated: animated)
        tabs.loadTabs()
        if tab != .chats { tabs.select(tab) }

        if let url {
            route(url, in: tabs)
        }
    }

    private func didSignIn(continuingTo url: URL? = nil) {
        // Several signals can report the same sign-in.
        guard case .signedOut = state else { return }

        memory.hasSignedIn = true
        let next = pendingURL ?? url
        pendingURL = nil
        // Without a link into an organization, the tabs start unprefixed and
        // the server picks the organization this person used last.
        let target = next.map(AppRoute.init(url:))
        showSignedIn(account: target?.account, continuingTo: next.flatMap { opensOnTop(of: $0) ? $0 : nil })
        PushNotifications.shared.refreshRegistrationIfAuthorized()
    }

    /// New chat opens as a sheet over the Chats tab, so the chat it starts
    /// lands in Chats when the sheet goes away.
    private func startNewChat(in tabs: MainTabBarController) {
        tabs.select(.chats)
        guard let navigator = tabs.navigator(for: .chats) else { return }
        navigator.route(environment.url(path: AppTab.path(AppTab.newChat.path, in: account)))
    }

    private func switchAccount(to target: AccountSlug, continuingTo url: URL) {
        guard target != account else { return }
        memory.lastAccount = target
        let route = AppRoute(url: url)
        showSignedIn(
            account: target,
            selecting: route.preferredTab ?? .chats,
            continuingTo: opensOnTop(of: url) ? url : nil
        )
    }

    /// Tab roots and the new chat page aren't pushed after a rebuild: the tab
    /// already shows the first, and the second is what an organization
    /// switcher links to, where the list is the better landing.
    private func opensOnTop(of url: URL) -> Bool {
        switch AppRoute(url: url).kind {
        case .tabRoot, .newChat, .authentication, .historicalLocation: false
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

        if case .historicalLocation = route.kind {
            showNotice(in: proposal.url)
            if case .signedOut = state {
                later { $0.didSignIn() }
                return .reject
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

        case .signedIn(let tabs):
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

            // Another tab's list is a tab switch, not a push.
            if case .tabRoot(let tab) = route.kind, tab != tabs.selectedAppTab, proposal.context == .default {
                later { _ in tabs.select(tab, popToRoot: true) }
                return .reject
            }

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
        case .signedIn(let tabs):
            // Servers that redirect a signed-out request to the sign-in form
            // instead of answering 401 still land here.
            let locations = tabs.navigators.flatMap { [$0.session.webView.url, $0.modalSession.webView.url] }.compactMap { $0 }
            if locations.contains(where: { AppRoute(url: $0).isSignIn }) {
                later { $0.showSignedOut(reason: .sessionExpired) }
                return
            }

            if account == nil, let current = tabs.navigator(for: tabs.selectedAppTab)?.session.webView.url,
               let slug = AppRoute(url: current).account {
                account = slug
                memory.lastAccount = slug
            }

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
        case .tabRoot, .newChat, .chat, .historicalLocation(.recede): return true
        default: return route.path == "/accounts"
        }
    }
}
