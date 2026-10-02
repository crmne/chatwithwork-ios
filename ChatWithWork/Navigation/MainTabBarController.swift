import HotwireNative
import UIKit

/// The signed-in shell: one navigator per tab, plus New chat as an action.
///
/// Tabs load lazily: only the selected one visits its page at launch, the
/// others the first time they're shown. The shell is rebuilt, not patched,
/// whenever the session or the organization changes (AppShell).
final class MainTabBarController: HotwireTabBarController {
    let account: AccountSlug?
    var onNewChat: (() -> Void)?

    private let environment: AppEnvironment
    private var hotwireTabs: [AppTab: HotwireTab] = [:]

    init(environment: AppEnvironment, account: AccountSlug?, navigatorDelegate: NavigatorDelegate) {
        self.environment = environment
        self.account = account
        super.init(navigatorDelegate: navigatorDelegate, lazyLoadTabs: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.canvas
        if #available(iOS 18.0, *) {
            mode = .tabBar
        }
        if #available(iOS 26.0, *) {
            // Lists get the whole screen while you scroll them.
            tabBarMinimizeBehavior = .onScrollDown
        }
    }

    /// Creates the tabs and starts the first one.
    func loadTabs() {
        let tabs = AppTab.allCases.map { tab in
            let hotwireTab = HotwireTab(
                id: tab.rawValue,
                title: tab.title,
                image: tab.image,
                selectedImage: tab.selectedImage,
                url: tab.url(in: environment, account: account)
            )
            hotwireTabs[tab] = hotwireTab
            return hotwireTab
        }

        load(tabs)
    }

    // MARK: Tabs

    func navigator(for tab: AppTab) -> Navigator? {
        hotwireTabs[tab].flatMap { navigator(for: $0) }
    }

    var navigators: [Navigator] {
        AppTab.destinations.compactMap { navigator(for: $0) }
    }

    var selectedAppTab: AppTab {
        if #available(iOS 18.0, *), let identifier = selectedTab?.identifier {
            return AppTab(rawValue: identifier) ?? .chats
        }
        return AppTab.allCases.indices.contains(selectedIndex) ? AppTab.allCases[selectedIndex] : .chats
    }

    /// Shows `tab`, starting its navigator if this is its first appearance.
    func select(_ tab: AppTab, popToRoot: Bool = false) {
        guard !tab.isAction else { return }

        if #available(iOS 18.0, *) {
            if let match = tabs.first(where: { $0.identifier == tab.rawValue }) {
                selectedTab = match
            }
        } else if let index = AppTab.allCases.firstIndex(of: tab) {
            selectedIndex = index
        }

        guard let navigator = navigator(for: tab) else { return }
        navigator.start()
        if popToRoot {
            navigator.rootViewController.dismiss(animated: false)
            navigator.rootViewController.popToRootViewController(animated: true)
        }
    }

    // MARK: New chat

    private func shouldSelect(_ tab: AppTab?) -> Bool {
        guard tab == .newChat else { return true }
        onNewChat?()
        return false
    }
}

extension MainTabBarController {
    @objc(tabBarController:shouldSelectViewController:)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        let index = tabBarController.viewControllers?.firstIndex(of: viewController)
        return shouldSelect(index.flatMap { AppTab.allCases.indices.contains($0) ? AppTab.allCases[$0] : nil })
    }

    @available(iOS 18.0, *)
    @objc(tabBarController:shouldSelectTab:)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        shouldSelect(AppTab(rawValue: tab.identifier))
    }
}
