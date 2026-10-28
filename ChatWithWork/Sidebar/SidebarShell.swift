import HotwireNative
import SwiftUI
import UIKit

/// The signed-in shell for one organization: a single navigator whose root
/// is always a chat (the path configuration's `replace_root` for
/// `/chats/new` and `/chats/<number>`), and the sidebar, which slides in from
/// the left and pushes the chat aside. Bots, projects and the other pages
/// are pushed over the chat; Settings and forms come up as sheets.
///
/// Opened by the bar's sidebar button or a swipe from the screen's left
/// edge; closed by a tap or a swipe on the chat, or by picking something.
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
    private var sidebarHost: UIHostingController<SidebarHostView>!
    private var sidebarLeading: NSLayoutConstraint!
    private var sidebarWidthConstraint: NSLayoutConstraint!
    private var progress: CGFloat = 0
    private var panStart: CGFloat = 0
    nonisolated(unsafe) private var pollTask: Task<Void, Never>?
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

    var isOpen: Bool { progress > 0.5 }

    init(environment: AppEnvironment, account: AccountSlug?, navigatorDelegate: NavigatorDelegate, memory: SessionMemory = .standard) {
        self.environment = environment
        self.account = account
        self.memory = memory
        store = SidebarStore(environment: environment, account: account, memory: memory)
        navigator = Navigator(
            configuration: .init(name: "main", startLocation: Self.startURL(environment: environment, account: account, memory: memory)),
            delegate: navigatorDelegate
        )
        super.init(nibName: nil, bundle: nil)
        Self.current = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        pollTask?.cancel()
        foregroundObserver.map(NotificationCenter.default.removeObserver)
    }

    /// The new chat in the list last chosen in this organization (its
    /// project, if it was one), or the server's pick of organization.
    static func startURL(environment: AppEnvironment, account: AccountSlug?, memory: SessionMemory) -> URL {
        let path = account.flatMap { memory.newChatPath(in: $0) } ?? AppPath.path(AppPath.newChat, in: account)
        return environment.url(path: path)
    }

    private var sidebarWidth: CGFloat { min(view.bounds.width * 0.84, 340) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.canvasSunken

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

        let host = UIHostingController(rootView: SidebarHostView(store: store, actions: actions, currentPath: { [weak self] in self?.currentPath }))
        host.view.backgroundColor = Palette.canvasSunken
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.accessibilityViewIsModal = true
        host.view.isHidden = true
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        sidebarHost = host

        sidebarLeading = host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        sidebarWidthConstraint = host.view.widthAnchor.constraint(equalToConstant: 300)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.widthAnchor.constraint(equalTo: view.widthAnchor),
            content.leadingAnchor.constraint(equalTo: host.view.trailingAnchor),
            main.view.topAnchor.constraint(equalTo: content.topAnchor),
            main.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            main.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            main.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            dim.topAnchor.constraint(equalTo: content.topAnchor),
            dim.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
                self?.store.markStale()
                if self?.isOpen == true { self?.refreshSidebar() }
            }
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

    /// Starts the navigator at the new chat, or reopens a chat left moments
    /// ago that is still answering or waiting for the person.
    func start() {
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

    // MARK: What the screens put in their bars

    /// The sidebar button on the leading side of a root screen, and New
    /// chat on the trailing side of every main-stack screen.
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
            newChat: { [weak self] in self?.startNewChat() },
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

    private func open(path: String) {
        setOpen(false, animated: true)
        navigator.route(environment.url(path: path))
    }

    func startNewChat() {
        setOpen(false, animated: true)
        let path = store.newChatPath ?? account.flatMap { memory.newChatPath(in: $0) } ?? AppPath.path(AppPath.newChat, in: account)
        navigator.route(environment.url(path: path))
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

    // MARK: The sidebar's list

    func sidebarChanged() {
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
                guard let self, self.isOpen, !Task.isCancelled else { return }
                if self.store.data?.isAnythingWorking == true { await self.store.refresh() }
            }
        }
    }

    // MARK: Opening and closing

    func toggle() {
        setOpen(!isOpen, animated: true)
    }

    func setOpen(_ open: Bool, animated: Bool) {
        if open {
            view.endEditing(true)
            Task { await store.refreshIfStale() }
            pollWhileOpen()
        } else {
            pollTask?.cancel()
        }
        let target: CGFloat = open ? 1 : 0
        guard animated else {
            apply(progress: target)
            return
        }
        prepareForMotion()
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.apply(progress: target, settled: false)
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.apply(progress: self.progress)
        }
    }

    private func prepareForMotion() {
        sidebarHost.view.isHidden = false
        dim.isHidden = false
    }

    /// Puts the sidebar `value` of the way open. Once `settled`, a closed
    /// sidebar and its dimming leave the screen (and the accessibility tree).
    private func apply(progress value: CGFloat, settled: Bool = true) {
        progress = min(max(value, 0), 1)
        sidebarLeading.constant = -sidebarWidth * (1 - progress)
        dim.alpha = 0.28 * progress
        if settled {
            let resting = progress == 0
            sidebarHost.view.isHidden = resting
            dim.isHidden = resting
        }
        content.layer.cornerRadius = 22 * progress
        content.layer.cornerCurve = .continuous
        navigator.rootViewController.view.accessibilityElementsHidden = progress == 1
        if settled, progress == 1 {
            UIAccessibility.post(notification: .screenChanged, argument: sidebarHost.view)
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
            if opening { view.endEditing(true); Task { await store.refreshIfStale() } }
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

    /// The edge swipe opens the sidebar only on a root screen with nothing
    /// over it; elsewhere the edge is the back swipe.
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
