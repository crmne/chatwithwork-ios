import UIKit
import WebKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var shell: AppShell?
    #if DEBUG
        private var showedActivityPreview = false
    #endif

    func sceneDidBecomeActive(_ scene: UIScene) {
        #if DEBUG
            if !showedActivityPreview, let scenario = UserDefaults.standard.string(forKey: "CWWLiveActivityPreview") {
                showedActivityPreview = true
                LiveActivities.preview(scenario)
            }
        #endif
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.tintColor = Palette.ink
        window.backgroundColor = Palette.canvas
        self.window = window

        let placeholder = UIViewController()
        placeholder.view.backgroundColor = Palette.canvas
        window.rootViewController = placeholder
        guard !LaunchOptions.isUnitTesting else {
            window.makeKeyAndVisible()
            return
        }

        let shell = AppShell(window: window, environment: .current)
        self.shell = shell
        window.makeKeyAndVisible()
        ToastCenter.shared.attach(to: windowScene)

        let link = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?.webpageURL
        let appLink = connectionOptions.urlContexts.first?.url
        // A notification that launched the app: the shell starts on its page.
        let launch = connectionOptions.notificationResponse.flatMap { response in
            PushNotifications.shared.takeLaunch(path: response.notification.request.content.userInfo["path"] as? String,
                                                identifier: response.notification.request.identifier)
        }
        let quickAction = connectionOptions.shortcutItem.flatMap { Shortcut(rawValue: $0.type) }
        let receiver: (Shortcut) -> Void = { [weak self] in self?.shell?.open($0) }
        let start = {
            if let shortcut = quickAction ?? ShortcutInbox.take() {
                shell.start(opening: shortcut)
            } else {
                shell.start(at: launch)
            }
            if let link { shell.open(link) }
            if let appLink { shell.openAppLink(appLink) }
            ShortcutInbox.receiver = receiver
        }

        if LaunchOptions.resetsState {
            // A fresh install's state includes no cookies: forget the session
            // before the first page asks for it.
            Task {
                await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                start()
            }
        } else {
            start()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ShortcutInbox.receiver = nil
    }

    /// A Home Screen quick action while the app is running.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard let shortcut = Shortcut(rawValue: shortcutItem.type) else { return completionHandler(false) }
        shell?.open(shortcut)
        completionHandler(true)
    }

    /// The app's own links: a widget, a Live Activity, the share extension.
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard let url = contexts.first?.url else { return }
        shell?.openAppLink(url)
    }

    /// Universal links while the app is running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else { return }
        shell?.open(url)
    }
}
