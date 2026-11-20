import HotwireNative
import SafariServices
import SwiftUI
import UIKit

/// The signed-in shell for one organization: a single navigator whose root
/// is the place on screen (a chat, Decisions, Bots, Settings, or whatever
/// else the sidebar opened: Places), and the sidebar, which slides in from
/// the left and pushes the root aside. The sidebar is the server's sidebar
/// page in a web view of its own (`SidebarWebController`) where the server
/// names one, else the native one drawn from its JSON. Drill-downs from a place (a bot from
/// Bots, New chat from the bar) are pushed over it with back; forms come up
/// as sheets.
///
/// Opened by the bar's sidebar button or a swipe from the screen's left
/// edge, on the root; closed by a tap or a swipe on the screen, or by
/// picking something.
/// Rebuilt, not patched, when the session or the organization changes
/// (AppShell).
final class SidebarShell: UIViewController, UIGestureRecognizerDelegate {
    /// The shell on screen, for the screens and components that put its
    /// buttons in their bars.
    private(set) static weak var current: SidebarShell?

    let account: AccountSlug?
    let navigator: Navigator
    let store: SidebarStore

    private let environment: AppEnvironment
    private let memory: SessionMemory
    private let content = UIView()
    private let dim = UIView()
    private let sidebarPanel = UIView()
    private var sidebarHost: UIHostingController<SidebarHostView>!
    private var sidebarPage: SidebarWebController!
    private var sidebarLeading: NSLayoutConstraint!
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var progress: CGFloat = 0
    private var panStart: CGFloat = 0
    /// Counts the drawer's slides, so only the latest one's end is its end.
    private var motion = 0
    private var isMoving = false
    /// What waits for the drawer to come to rest.
    private var afterMotion: [() -> Void] = []
    /// Counts the visits the shell starts, so a New chat waiting for the
    /// drawer gives way to anything opened meanwhile.
    private var visits = 0
    nonisolated(unsafe) private var pollTask: Task<Void, Never>?
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

    var isOpen: Bool { progress > 0.5 }
    /// Whether the drawer showed since it last came to rest closed.
    private var drawerShown = false

    /// Signing out from the person's menu in the sidebar page (AppShell).
    var onSignOut: (() -> Void)?

    /// Whether the drawer shows the server's sidebar page, which keeps itself
    /// live, rather than the native one, which fetches its JSON.
    var showsSidebarPage: Bool { sidebarPage?.isReady == true }

    /// While the shell opens a page by itself (New chat for a server without
    /// the home), which takes no keyboard.
    private(set) var opensByItself = false

    init(environment: AppEnvironment, account: AccountSlug?, navigatorDelegate: NavigatorDelegate, memory: SessionMemory = .standard) {
        self.environment = environment
        self.account = account
        self.memory = memory
        store = SidebarStore(environment: environment, account: account, memory: memory)
        navigator = Navigator(
            configuration: .init(name: "main", startLocation: Self.startURL(environment: environment, account: account, memory: memory)),
            delegate: navigatorDelegate
        )
        // The web composer's dictation records in the page.
        navigator.webkitUIDelegate = WebUIController(delegate: navigator, server: environment.baseURL)
        super.init(nibName: nil, bundle: nil)
        Self.current = self
        // Another organization's count isn't this one's.
        DecisionsButton.reset()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        pollTask?.cancel()
        foregroundObserver.map(NotificationCenter.default.removeObserver)
    }

    /// The organization's home, which lands on Decisions (docs/server-contract.md,
    /// "Where the app starts"), or the server's pick of organization.
    static func startURL(environment: AppEnvironment, account: AccountSlug?, memory: SessionMemory) -> URL {
        environment.url(path: AppPath.path(AppPath.home, in: account))
    }

    /// Where to start instead when the organization's home answers 404: a
    /// server older than it (self-hosted releases before 2026-11-17) starts
    /// on the new chat last chosen in that organization, a place, as builds
    /// before the home did. None for any other page.
    static func startURLWithoutHome(failed url: URL, environment: AppEnvironment, account: AccountSlug?, memory: SessionMemory) -> URL? {
        let route = AppRoute(url: url)
        guard route.path == AppPath.home else { return nil }
        let account = route.account ?? account
        let path = account.flatMap { memory.newChatPath(in: $0) } ?? AppPath.path(AppPath.newChat, in: account)
        return environment.url(path: path)
    }

    /// Opens New chat in place of a home the server doesn't have, as
    /// the place at the root. False when `url` isn't the home. A sidebar
    /// opened while the home loaded stays open: the person didn't pick this.
    func startWithoutHome(failed url: URL) -> Bool {
        guard let start = Self.startURLWithoutHome(failed: url, environment: environment, account: account, memory: memory) else { return false }
        opensByItself = true
        defer { opensByItself = false }
        open(url: start, closingSidebar: false)
        return true
    }

    private var sidebarWidth: CGFloat { Self.sidebarWidth(in: view.bounds.width, category: traitCollection.preferredContentSizeCategory) }

    /// Most of a phone's width, up to 340 points; at the accessibility text
    /// sizes nearly all of it, up to 420, so names keep a few words a line.
    static func sidebarWidth(in width: CGFloat, category: UIContentSizeCategory) -> CGFloat {
        category.isAccessibilityCategory ? min(width * 0.92, 420) : min(width * 0.84, 340)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.canvasSunken
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (shell: SidebarShell, _: UITraitCollection) in
            shell.view.setNeedsLayout()
        }

        content.translatesAutoresizingMaskIntoConstraints = false
        content.backgroundColor = Palette.canvas
        content.clipsToBounds = true
        view.addSubview(content)

        let main = navigator.rootViewController
        addChild(main)
        main.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main.view)
        main.didMove(toParent: self)

        dim.translatesAutoresizingMaskIntoConstraints = false
        dim.backgroundColor = UIColor.black
        dim.alpha = 0
        dim.isHidden = true
        dim.accessibilityLabel = String(localized: "Close sidebar")
        dim.accessibilityTraits = .button
        dim.isAccessibilityElement = true
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeTapped)))
        dim.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panToClose(_:))))
        content.addSubview(dim)

        sidebarPanel.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.backgroundColor = Palette.canvasSunken
        sidebarPanel.accessibilityViewIsModal = true
        sidebarPanel.isHidden = true
        view.addSubview(sidebarPanel)

        let host = UIHostingController(rootView: SidebarHostView(store: store, actions: actions, currentPath: { [weak self] in self?.currentPath }))
        host.view.backgroundColor = Palette.canvasSunken
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        sidebarPanel.addSubview(host.view)
        host.didMove(toParent: self)
        sidebarHost = host

        // Over the native sidebar, inside the safe area, shown once its page is drawn.
        let page = SidebarWebController(environment: environment)
        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        page.view.isHidden = true
        sidebarPanel.addSubview(page.view)
        page.didMove(toParent: self)
        sidebarPage = page
        wireSidebarPage()

        sidebarLeading = sidebarPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        sidebarWidthConstraint = sidebarPanel.widthAnchor.constraint(equalToConstant: 300)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.widthAnchor.constraint(equalTo: view.widthAnchor),
            content.leadingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor),
            main.view.topAnchor.constraint(equalTo: content.topAnchor),
            main.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            main.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            main.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            dim.topAnchor.constraint(equalTo: content.topAnchor),
            dim.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sidebarPanel.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.topAnchor.constraint(equalTo: sidebarPanel.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: sidebarPanel.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor),
            page.view.topAnchor.constraint(equalTo: sidebarPanel.safeAreaLayoutGuide.topAnchor),
            page.view.bottomAnchor.constraint(equalTo: sidebarPanel.safeAreaLayoutGuide.bottomAnchor),
            page.view.leadingAnchor.constraint(equalTo: sidebarPanel.safeAreaLayoutGuide.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor),
            sidebarWidthConstraint,
            sidebarLeading
        ])

        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePan(_:)))
        edge.edges = .left
        edge.delegate = self
        view.addGestureRecognizer(edge)

        store.onSignedOut = { [weak self] in
            self?.navigator.reload()
        }
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.showsSidebarPage {
                    self.sidebarPage.refresh()
                    return
                }
                self.sidebarPage.retryIfNeverReady()
                self.store.markStale()
                if self.isOpen { self.refreshSidebar() }
            }
        }
        // The page the server named here last time, at once, before the first page connects.
        if let account, let path = memory.sidebarPagePath(in: account) {
            sidebarPage.load(environment.url(path: path))
        }
        apply(progress: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if sidebarWidthConstraint.constant != sidebarWidth {
            sidebarWidthConstraint.constant = sidebarWidth
            apply(progress: progress)
        }
    }

    /// Starts the navigator at `url` when a notification, a shortcut or a
    /// share launched the app onto it (New chat among them; a form comes up
    /// over the home), else at
    /// the home, or reopens a chat left moments ago that is still answering
    /// or waiting for the person.
    func start(at url: URL? = nil) {
        if let url {
            let properties = navigator.session.pathConfiguration?.properties(for: url) ?? PathProperties()
            if let place = Self.startingPlace(url, properties: properties) {
                // The page's own screen first, its visit started at once:
                // New chat loading first only to be replaced cost a whole page load.
                navigator.route(place)
            } else {
                // A form comes up over the shell's usual start.
                navigator.start()
                navigator.route(url)
            }
            return
        }

        guard let (path, at) = memory.lastChat, Date().timeIntervalSince(at) < 10 * 60,
              AppRoute(path: path).account == account, AppRoute(path: path).isChat
        else {
            navigator.start()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let check = Task { await self.store.refresh() }
            // Never hold the first screen for long on a slow network.
            let deadline = Task { try? await Task.sleep(for: .seconds(1.5)); check.cancel() }
            await check.value
            deadline.cancel()
            let chat = self.store.data.flatMap { data in (data.pins + data.chats).first { AppRoute(path: $0.url).path == AppRoute(path: path).path } }
            self.navigator.start()
            if let chat, chat.isWorking || chat.isWaiting {
                self.navigator.route(self.environment.url(path: chat.url))
            }
        }
    }

    /// The visit that starts the navigator on `url`, as the place at its
    /// root; none for a page that comes up as a form (a modal).
    nonisolated static func startingPlace(_ url: URL, properties: PathProperties) -> VisitProposal? {
        guard properties.context != .modal else { return nil }
        return VisitProposal(url: url, options: VisitOptions(action: .advance), properties: Places.opening(properties))
    }

    // MARK: What the screens put in their bars

    /// The sidebar button on the leading side of the root screen, the place
    /// on screen, where back would be, and New chat on the trailing side of
    /// every main-stack screen.
    func decorate(_ viewController: UIViewController, isRoot: Bool) {
        if isRoot {
            let sidebar = UIBarButtonItem(image: UIImage(systemName: "sidebar.left"), primaryAction: UIAction { [weak self] _ in self?.toggle() })
            sidebar.accessibilityLabel = String(localized: "Open sidebar")
            sidebar.accessibilityIdentifier = "shell.sidebar"
            NavigationBarItems.set(sidebar, slot: .shell, side: .leading, on: viewController)
        }
        if store.data?.links.newChat != nil || store.data == nil {
            let newChat = UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), primaryAction: UIAction { [weak self] _ in self?.startNewChat() })
            newChat.accessibilityLabel = String(localized: "New chat")
            newChat.accessibilityIdentifier = "shell.newChat"
            NavigationBarItems.set(newChat, slot: .shell, side: .trailing, on: viewController)
        }
    }

    // MARK: Routing

    private var actions: SidebarActions {
        SidebarActions(
            open: { [weak self] path in self?.open(path: path) },
            newChat: { [weak self] in self?.openNewChat() },
            chooseList: { [weak self] key in
                guard let self else { return }
                Task {
                    await self.store.choose(list: key)
                    // New chat now starts in the chosen list's project.
                    if case .newChat = AppRoute(url: self.navigator.rootViewController.viewControllers.first?.routedURL ?? self.environment.baseURL).kind,
                       let newChat = self.store.newChatPath, self.navigator.rootViewController.viewControllers.count == 1 {
                        self.navigator.route(self.environment.url(path: newChat))
                    }
                }
            },
            perform: { [weak self] action in self?.perform(action) },
            toggleSection: { [weak self] section in self?.toggle(section) }
        )
    }

    /// Opens or closes one of the person's sections: at once here, and on
    /// the server through the page on screen, so every device shows it so.
    private func toggle(_ section: SidebarData.Section) {
        guard let action = section.toggleAction else { return }
        store.setCollapsed(!section.collapsed, section: section.id)
        perform(action)
    }

    /// A chat's action from the sidebar: a page opens as any link would;
    /// anything else (Pin, Delete) goes to the page on screen to send, which
    /// asks first where the action says so, and the sidebar follows the
    /// change through `changed`.
    private func perform(_ action: SidebarData.Action) {
        if action.opensPage {
            open(path: action.url)
            return
        }
        if action.confirm != nil { setOpen(false, animated: true) }
        let main = navigator.rootViewController
        if !SidebarComponent.perform(action, on: main.topViewController) {
            ToastCenter.shared.show(String(localized: "That didn't work. Open a chat and try again."), style: .alert)
        }
    }

    /// What the sidebar opens is a place: the root screen, never pushed over
    /// what was there (Places).
    private func open(path: String) {
        open(url: environment.url(path: path))
    }

    /// New chat and New bot wait for the drawer to slide shut and the screen
    /// without it to be drawn, so their page and its keyboard don't arrive
    /// while it moves (docs/server-contract.md, "New chat and New bot").
    private func open(url: URL, closingSidebar: Bool = true) {
        let properties = navigator.session.pathConfiguration?.properties(for: url) ?? PathProperties()
        let place = VisitProposal(url: url, options: VisitOptions(action: .advance), properties: Places.opening(properties))
        let route = AppRoute(url: url)
        let visit = startingVisit()
        guard closingSidebar else {
            navigator.route(place)
            return
        }
        guard route.kind == .newChat || route.isNewBot, progress > 0 || isMoving else {
            setOpen(false, animated: true)
            navigator.route(place)
            return
        }
        setOpen(false, animated: true) { [weak self] in
            DispatchQueue.main.async {
                guard let self, visit == self.visits else { return }
                self.navigator.route(place)
            }
        }
    }

    /// Notes a visit the shell or a link starts, which a New chat still
    /// waiting for the drawer gives way to; answers its number.
    @discardableResult
    func startingVisit() -> Int {
        visits += 1
        return visits
    }

    /// New chat from the bar: pushed over the page on screen, with back to it
    /// (the path configuration). One already on top takes the keyboard,
    /// keeping its words, rather than another stacking on it.
    func startNewChat() {
        startingVisit()
        setOpen(false, animated: true)
        if let composer = ComposerController.onNewChat(navigator.rootViewController) {
            composer.focus()
            return
        }
        // The web composer's New chat keeps its words too.
        if showsNewChat { return }
        navigator.route(environment.url(path: newChatPath))
    }

    /// Whether New chat is on top of the main stack, with nothing over it.
    var showsNewChat: Bool {
        let main = navigator.rootViewController
        guard main.presentedViewController == nil, let top = main.topViewController as? VisitableViewController else { return false }
        return AppRoute(url: top.currentVisitableURL).kind == .newChat
    }

    /// New chat as a place, the root: the sidebar's, a shortcut's, a share's
    /// (`url`, with what it brings in its query), opened once the drawer has
    /// shut. One already on top takes the keyboard instead.
    func openNewChat(_ url: URL? = nil) {
        if url?.query() == nil, let composer = ComposerController.onNewChat(navigator.rootViewController) {
            setOpen(false, animated: true)
            composer.focus()
            return
        }
        if url?.query() == nil, showsNewChat {
            setOpen(false, animated: true)
            return
        }
        open(url: url ?? environment.url(path: newChatPath))
    }

    /// The organization's home as the place at the root: where a chat that
    /// went away leaves the person.
    func openHome() {
        open(url: Self.startURL(environment: environment, account: account, memory: memory))
    }

    /// Where New chat goes: the bar's button, the shortcuts, a recede with
    /// nothing under it. The native sidebar's chosen list may be a project's,
    /// and New chat starts in it; the sidebar page has no such choice, and
    /// its New chat is the organization's, so with the page in the drawer
    /// so is the bar's, never a project the native sidebar chose before.
    var newChatPath: String {
        Self.newChatPath(usesSidebarPage: sidebarPage?.pageURL != nil, chosen: store.newChatPath ?? account.flatMap { memory.newChatPath(in: $0) }, account: account)
    }

    static func newChatPath(usesSidebarPage: Bool, chosen: String?, account: AccountSlug?) -> String {
        let plain = AppPath.path(AppPath.newChat, in: account)
        return usesSidebarPage ? plain : chosen ?? plain
    }

    /// The page on screen, as a path, to mark its row.
    var currentPath: String? {
        navigator.activeWebView.url?.path(percentEncoded: false)
    }

    /// Notes the chat on screen, so a launch soon after can come back to it.
    func noteVisit(_ url: URL) {
        let route = AppRoute(url: url)
        if case .chat = route.kind {
            memory.lastChat = (url.path(percentEncoded: false), Date())
        } else if route.kind == .newChat {
            memory.lastChat = nil
        }
    }

    // MARK: The sidebar page

    private func wireSidebarPage() {
        sidebarPage.onReady = { [weak self] in self?.showSidebarPage(true) }
        sidebarPage.onUnavailable = { [weak self] in self?.showSidebarPage(false) }
        sidebarPage.onClose = { [weak self] in self?.setOpen(false, animated: true) }
        sidebarPage.onVisit = { [weak self] url in self?.open(url: url) }
        sidebarPage.onExternal = { [weak self] url in self?.openOutside(url) }
        sidebarPage.onSignedOut = { [weak self] deliberate in
            guard let self else { return }
            self.setOpen(false, animated: false)
            if deliberate, let onSignOut = self.onSignOut {
                onSignOut()
            } else {
                // The page's own load found no session: the navigator's next
                // visit finds the same, and the app signs out as for any page.
                self.navigator.reload()
            }
        }
    }

    /// A link off this server from the sidebar page (Help, a vendor's page):
    /// a web page opens in Safari's sheet over the app, never in the drawer
    /// or the navigator; mail and phone links go to their apps.
    private func openOutside(_ url: URL) {
        guard SidebarPage.opensInSafariSheet(url) else {
            UIApplication.shared.open(url)
            return
        }
        setOpen(false, animated: true)
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController { presenter = presented }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = Palette.ink
        presenter.present(safari, animated: true)
    }

    private func showSidebarPage(_ shows: Bool) {
        sidebarPage.view.isHidden = !shows
        sidebarHost.view.isHidden = shows
        if shows {
            pollTask?.cancel()
        } else if isOpen {
            refreshSidebar()
            pollWhileOpen()
        }
    }

    /// A page's `sidebar` component connected: the drawer follows the sidebar
    /// page it names (an older server names none: the native sidebar), and
    /// marks the row of the page on screen. Only the main stack's pages
    /// count; a sheet's page isn't the one the sidebar opened.
    func sidebarPageNamed(_ connect: SidebarPage.Connect, by screen: UIViewController?, at url: URL?) {
        let main = navigator.rootViewController
        guard let screen, main.viewControllers.contains(screen) else { return }

        switch SidebarPage.choose(connect, loaded: sidebarPage.pageURL?.path(percentEncoded: false)) {
        case .native:
            if let account { memory.setSidebarPagePath(nil, in: account) }
            sidebarPage.unload()
            showSidebarPage(false)
        case .load(let path):
            if let account { memory.setSidebarPagePath(path, in: account) }
            sidebarPage.load(environment.url(path: path))
        case .keep:
            sidebarPage.retryIfNeverReady()
        }
        if let url = url ?? screen.routedURL, main.topViewController === screen {
            sidebarPage.setCurrent(url, belongsTo: connect.belongsTo)
        }
    }

    // MARK: The sidebar's list

    func sidebarChanged() {
        // The sidebar page hears the same streams itself.
        if showsSidebarPage { return }
        store.markStale()
        if isOpen { refreshSidebar() }
    }

    private func refreshSidebar() {
        Task { await store.refresh() }
    }

    /// While the sidebar is open and a chat or bot in it works, check again
    /// every few seconds, so its dot goes out when the work ends.
    private func pollWhileOpen() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isOpen, !self.showsSidebarPage, !Task.isCancelled else { return }
                if self.store.data?.isAnythingWorking == true { await self.store.refresh() }
            }
        }
    }

    // MARK: Opening and closing

    func toggle() {
        setOpen(!isOpen, animated: true)
    }

    /// `completion` runs once the drawer is at rest, after this slide or any
    /// that takes over from it.
    func setOpen(_ open: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        if open {
            view.endEditing(true)
            if !showsSidebarPage {
                Task { await store.refreshIfStale() }
                pollWhileOpen()
            }
        } else {
            pollTask?.cancel()
            releaseSidebarFocus()
        }
        let target: CGFloat = open ? 1 : 0
        if let completion { afterMotion.append(completion) }
        motion += 1
        guard animated else {
            apply(progress: target)
            settle()
            return
        }
        let slide = motion
        isMoving = true
        prepareForMotion()
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.apply(progress: target, settled: false)
            self.view.layoutIfNeeded()
        } completion: { _ in
            guard slide == self.motion else { return }
            self.apply(progress: self.progress)
            self.settle()
        }
    }

    private func settle() {
        isMoving = false
        let waiting = afterMotion
        afterMotion = []
        waiting.forEach { $0() }
    }

    private func prepareForMotion() {
        sidebarPanel.isHidden = false
        dim.isHidden = false
    }

    /// A closed sidebar's search field keeps nothing: left focused, it
    /// would hold the keyboard up and go on taking what's typed.
    private func releaseSidebarFocus() {
        sidebarPanel.endEditing(true)
    }

    /// Puts the sidebar `value` of the way open. Once `settled`, a closed
    /// sidebar and its dimming leave the screen (and the accessibility tree).
    private func apply(progress value: CGFloat, settled: Bool = true) {
        progress = min(max(value, 0), 1)
        if progress > 0 { drawerShown = true }
        sidebarLeading.constant = -sidebarWidth * (1 - progress)
        dim.alpha = 0.28 * progress
        if settled {
            let resting = progress == 0
            if resting {
                releaseSidebarFocus()
                // However it closed (a swipe, a tap beside it, a visit): the page
                // ends what it had open, row picking and its menus.
                if drawerShown { sidebarPage?.closed() }
                drawerShown = false
            }
            sidebarPanel.isHidden = resting
            dim.isHidden = resting
        }
        content.layer.cornerRadius = 22 * progress
        content.layer.cornerCurve = .continuous
        navigator.rootViewController.view.accessibilityElementsHidden = progress == 1
        if settled, progress == 1 {
            if showsSidebarPage { nudgeSidebarPage() }
            UIAccessibility.post(notification: .screenChanged, argument: showsSidebarPage ? sidebarPage.view : sidebarHost.view)
        }
    }

    /// WebKit keeps where the sidebar page sits on screen for VoiceOver and
    /// hit tests, and moving the drawer doesn't tell it: after the search had
    /// the keyboard and a row opened a chat, it went on reporting the page's
    /// elements where the closed drawer had them. Changing the page's width
    /// by a fraction and back makes it work its place out again.
    private func nudgeSidebarPage() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen, let page = self.sidebarPage.view else { return }
            page.frame.size.width -= 0.5
            page.layoutIfNeeded()
            // The constraints put it back.
            self.sidebarPanel.setNeedsLayout()
            self.sidebarPanel.layoutIfNeeded()
        }
    }

    @objc private func closeTapped() {
        setOpen(false, animated: true)
    }

    @objc private func edgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        interactive(recognizer, opening: true)
    }

    @objc private func panToClose(_ recognizer: UIPanGestureRecognizer) {
        interactive(recognizer, opening: false)
    }

    private func interactive(_ recognizer: UIPanGestureRecognizer, opening: Bool) {
        let dx = recognizer.translation(in: view).x
        switch recognizer.state {
        case .began:
            panStart = progress
            prepareForMotion()
            if opening {
                view.endEditing(true)
                if !showsSidebarPage { Task { await store.refreshIfStale() } }
            }
        case .changed:
            apply(progress: panStart + dx / sidebarWidth, settled: false)
            view.layoutIfNeeded()
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: view).x
            let open = velocity > 300 || (velocity > -300 && progress > 0.5)
            setOpen(open, animated: true)
        default:
            break
        }
    }

    /// The edge swipe opens the sidebar only on the root screen with nothing
    /// over it; on a drill-down the edge is the back swipe.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UIScreenEdgePanGestureRecognizer else { return true }
        let main = navigator.rootViewController
        return main.viewControllers.count <= 1 && main.presentedViewController == nil && progress == 0
    }
}

/// Re-reads the shell's current path whenever the store changes, so the row
/// of the chat on screen stays marked.
struct SidebarHostView: View {
    @Bindable var store: SidebarStore
    let actions: SidebarActions
    let currentPath: () -> String?

    var body: some View {
        SidebarView(store: store, actions: actions, currentPath: currentPath())
    }
}

extension UIViewController {
    /// The URL a navigator routed this screen to, when it's a web screen.
    var routedURL: URL? {
        (self as? VisitableViewController)?.currentVisitableURL
    }
}
