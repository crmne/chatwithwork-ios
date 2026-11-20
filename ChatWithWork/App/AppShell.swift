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
    /// The page a shortcut just opened, which signing in again comes back to
    /// if its visit finds the session gone.
    private var shortcutPage: URL?
    /// The main stack's screen whose page last started a form submission,
    /// to know a chat New chat turned into from any other visit (NewChatHandOff).
    private weak var formScreen: UIViewController?

    init(window: UIWindow, environment: AppEnvironment, memory: SessionMemory = .standard) {
        self.window = window
        self.environment = environment
        self.memory = memory
        super.init()
    }

    /// Puts up the first screen: `url`'s page, when a notification launched
    /// the app, or the shell's usual start.
    func start(at url: URL? = nil) {
        LiveActivities.shared.isSignedIn = { [weak self] in
            if case .signedIn = self?.state { true } else { false }
        }

        let url = url.flatMap { environment.owns($0) ? $0 : nil }
        if memory.hasSignedIn || LaunchOptions.assumesSignedIn {
            // Straight into the page's organization and onto the page, rather
            // than loading the home first only to replace it.
            let account = url.flatMap { AppRoute(url: $0).account } ?? memory.lastAccount
            if account != memory.lastAccount { memory.lastAccount = account }
            showSignedIn(account: account, startingAt: url, animated: false)
            PushNotifications.shared.refreshRegistrationIfAuthorized()
        } else {
            showSignedOut(reason: .firstLaunch, animated: false)
            if let url { pendingURL = url }
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

    // MARK: Shortcuts

    /// Puts up the first screen for a shortcut that launched the app: its page
    /// as the place at the root (New chat, Decisions), rather than loading the
    /// home or the chat left a moment ago first; New bot's comes over the home.
    func start(opening shortcut: Shortcut) {
        switch shortcut {
        case .newChat:
            ComposerController.focusesOnConnect = true
            start(at: page(for: shortcut))
        case .decisions:
            start(at: page(for: shortcut))
        case .newBot:
            start()
            open(shortcut)
        }
    }

    /// Opens a shortcut's page in the organization on screen.
    func open(_ shortcut: Shortcut, attempt: Int = 0) {
        // Launched by the shortcut: let the shell put up its first screen first.
        if case .signedIn(let shell) = state, shell.navigator.rootViewController.viewControllers.isEmpty, attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.open(shortcut, attempt: attempt + 1) }
            return
        }
        if shortcut == .newChat {
            ComposerController.focusesOnConnect = true
            _ = page(for: shortcut)
            // A new chat already on screen takes it without a visit, so nothing is left to settle.
            if case .signedIn(let shell) = state, ComposerController.onNewChat(shell.navigator.rootViewController) != nil { shortcutPage = nil }
            openAppLink(AppLink.newChat())
        } else {
            open(page(for: shortcut))
        }
    }

    /// The shortcut's page, remembered until its own visit finishes, so a
    /// session that ends meanwhile brings the person back to it after signing in.
    /// The newest shortcut replaces any earlier one still loading.
    private func page(for shortcut: Shortcut) -> URL {
        let account = account ?? currentAccount ?? memory.lastAccount
        var chosen: String?
        switch shortcut {
        case .newBot:
            if case .signedIn(let shell) = state { chosen = shell.store.newBotPath }
        case .newChat:
            if case .signedIn(let shell) = state { chosen = shell.newChatPath }
            chosen = chosen ?? account.flatMap { memory.newChatPath(in: $0) }
        case .decisions:
            break
        }
        let url = environment.url(path: shortcut.path(in: account, chosen: chosen))
        shortcutPage = url
        return url
    }

    /// A shortcut whose visit found the session gone opens once signed in again.
    private func keepShortcutPage() {
        if let shortcutPage { pendingURL = shortcutPage }
        shortcutPage = nil
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
            if value("dictate") == "1" { ComposerInbox.dictates = true }
            if let shared = value("shared") {
                ComposerInbox.files = SharedInbox.take(shared).map { ComposerFile(name: $0.name, type: $0.type, bytes: $0.data) }
            }
            // The words wait in the native composer too, whatever the page does with them.
            // Joined as the server joins them for `/chats/new`, so a composer it filled is recognized.
            var shared: [String] = []
            for word in ["title", "text", "url"].compactMap(value).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !word.isEmpty && !shared.contains(word) {
                shared.append(word)
            }
            let sharedText = shared.joined(separator: "\n\n")
            if !sharedText.isEmpty, BridgeRegistry.drawsComposer { ComposerInbox.text = sharedText }
            // A new chat already on screen takes them as they are. The web composer gets
            // shared words only in New chat's address, so words visit it again.
            if case .signedIn(let shell) = state, let composer = ComposerController.onNewChat(shell.navigator.rootViewController) {
                shell.setOpen(false, animated: false)
                composer.takePending()
                return
            }
            if case .signedIn(let shell) = state, sharedText.isEmpty, let composer = WebComposerComponent.onNewChat(shell.navigator.rootViewController) {
                shell.setOpen(false, animated: false)
                composer.takeInbox()
                shell.focusNewChat()
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

        shell.startingVisit()
        shell.setOpen(false, animated: false)
        if route.kind == .newChat {
            // A shortcut's, a share's, a link's: a place, as the sidebar opens it.
            shell.openNewChat(url)
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

    private func showSignedIn(account: AccountSlug?, continuingTo url: URL? = nil, startingAt start: URL? = nil, animated: Bool = true) {
        let shell = SidebarShell(environment: environment, account: account, navigatorDelegate: self, memory: memory)
        shell.onSignOut = { [weak self] in self?.later { $0.showSignedOut(reason: .signedOut) } }
        self.account = account
        state = .signedIn(shell)

        // In the window before the first page loads, so the page starts under
        // the bars at their real height.
        replaceRoot(with: shell, animated: animated)
        shell.start(at: start)

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
        // A page is waiting: the chat left moments ago mustn't come back over it.
        if next != nil { memory.lastChat = nil }
        // Without a link into an organization, the shell starts unprefixed and
        // the server picks the organization this person used last.
        let target = next.map(AppRoute.init(url:))
        showSignedIn(account: target?.account, continuingTo: next.flatMap { opensOnTop(of: $0) ? $0 : nil }, startingAt: next.flatMap(Self.startsAt))
        PushNotifications.shared.refreshRegistrationIfAuthorized()
    }

    private func switchAccount(to target: AccountSlug, continuingTo url: URL) {
        guard target != account else { return }
        // Words held for one organization's New chat don't follow into another's.
        KeyboardHandOff.discard()
        memory.lastAccount = target
        showSignedIn(account: target, continuingTo: opensOnTop(of: url) ? url : nil, startingAt: Self.startsAt(url))
    }

    /// A link to New chat starts the rebuilt shell on it, the place at the
    /// root (SidebarShell.start(at:)).
    static func startsAt(_ url: URL) -> URL? {
        AppRoute(url: url).kind == .newChat ? url : nil
    }

    /// New chat isn't opened again after a rebuild: the shell starts with
    /// it (startsAt). Nor is the chat list, which the sidebar replaced.
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
        SidebarCache.clear()
        NewChatDraft.clear()
        KeyboardHandOff.discard()
        account = nil
        PushNotifications.shared.forgetKey()
        LiveActivities.shared.endAll()

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
    /// historical location it sends the app to (`recede_`, `resume_` or
    /// `refresh_historical_location`). The page beneath isn't loaded again,
    /// so its flash would never show: the app shows it as a toast.
    private func showNotice(in url: URL) {
        guard let notice = Self.notice(in: url) else { return }
        ToastCenter.shared.show(notice.message, style: notice.style)
    }

    /// The notice, or else the alert, on a historical location's URL.
    static func notice(in url: URL) -> (message: String, style: ToastStyle)? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 } }
        if let notice = value("notice") { return (notice, .notice) }
        if let alert = value("alert") { return (alert, .alert) }
        return nil
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
            // under it, so the home takes its place rather than leaving the
            // deleted one up, as the server's own Delete does.
            if location == .recede, case .signedIn(let shell) = state {
                let main = shell.navigator.rootViewController
                if main.viewControllers.count <= 1, main.presentedViewController == nil {
                    later { _ in shell.openHome() }
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
                keepShortcutPage()
                later { $0.showSignedOut(reason: reason) }
                return .reject
            }

            if let target = route.account, let account, target != account {
                later { $0.switchAccount(to: target, continuingTo: proposal.url) }
                return .reject
            }

            let main = shell.navigator.rootViewController
            if NewChatHandOff.isHandOff(proposal) {
                shell.noteVisit(proposal.url)
                return .acceptCustom(NewChatHandOff.screen(for: proposal.url, replacing: main.topViewController))
            }
            let opensInPlace = NewChatHandOff.isOpeningInPlace(proposal)
            // The chat the page on top just turned into in place takes that
            // screen's place, rather than the place the configuration gives a chat.
            if main.presentedViewController == nil, let top = main.topViewController,
               NewChatHandOff.takes(proposal.url, hasResponse: proposal.options.response != nil, onTop: top.routedURL, submittedFromTop: top === formScreen) {
                formScreen = nil
                NewChatHandOff.route(proposal, on: shell.navigator)
                return .reject
            }
            // New chat opened by the person (a tap, a link, a shortcut) takes
            // the keyboard; not a page that arrives by itself, as a redirect,
            // unless it redirects a New chat that had it (an unprefixed
            // `/chats/new` going into the organization).
            if route.kind == .newChat, !main.viewControllers.isEmpty, !shell.opensByItself,
               proposal.options.response == nil || ComposerController.hasKeyboard(onNewChatIn: main) {
                ComposerController.focusesOnConnect = true
                // The page's own composer can't raise the keyboard by itself: the app takes it now.
                if !BridgeRegistry.drawsComposer, proposal.options.response == nil {
                    // The page on screen now is the one this New chat leaves, even if it's a New chat too.
                    let leaving = KeyboardHandOff.markLeaving(shell.navigator.session.webView)
                    shell.whenDrawerShut { [weak shell] in
                        guard let shell else { return }
                        KeyboardHandOff.raise(in: shell.view.window, for: shell.navigator.session.webView, leaving: leaving)
                    }
                }
            }
            // New chat and New bot opened from a page come up where it stands,
            // with Back to it: pushed without the slide, showing that page
            // until theirs has drawn.
            if opensInPlace {
                shell.noteVisit(proposal.url)
                return .acceptCustom(NewChatHandOff.screen(for: proposal.url, replacing: main.topViewController))
            }
            if NewChatHandOff.opensInPlace(proposal, hasScreens: !main.viewControllers.isEmpty, presenting: main.presentedViewController != nil) {
                shell.navigator.route(NewChatHandOff.openingInPlace(proposal))
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

    /// Notes whose form is going, for NewChatHandOff: Hotwire names the page
    /// of the session's screen on top, the main stack's or a sheet's.
    func formSubmissionDidStart(to url: URL) {
        guard case .signedIn(let shell) = state else { return }
        let main = shell.navigator.rootViewController
        guard main.presentedViewController == nil, let top = main.topViewController as? VisitableViewController,
              shell.navigator.session.topmostVisitable?.visitableViewController === top, top.initialVisitableURL == url
        else {
            formScreen = nil
            return
        }
        formScreen = top
    }

    func visitableDidFailRequest(_ visitable: Visitable, error: HotwireNativeError, retryHandler: RetryBlock?) {
        // A page that didn't load shows why, not its shape, nor the page it replaced.
        PageSkeleton.dismiss(on: visitable.visitableViewController, animated: false)
        NewChatHandOff.dismiss(on: visitable.visitableViewController, animated: false)
        if error.statusCode == 401 {
            switch state {
            case .signedIn:
                keepShortcutPage()
                later { $0.showSignedOut(reason: .sessionExpired) }
            case .signedOut(let flow):
                later { _ in flow.presentSignIn() }
            case .launching:
                break
            }
            return
        }
        // A server older than the organization's home (docs/server-contract.md,
        // "Where the app starts") starts on New chat instead.
        if error.statusCode == 404, case .signedIn(let shell) = state, shell.startWithoutHome(failed: visitable.currentVisitableURL) {
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
                keepShortcutPage()
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
            // Only the shortcut's own visit settles it; another page finishing meanwhile doesn't.
            if let page = shortcutPage, AppRoute(url: url).path == AppRoute(url: page).path { shortcutPage = nil }

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
        default: return route.path == "/accounts" || route.path == AppPath.home
        }
    }
}
