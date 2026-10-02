import UIKit
import WebKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var shell: AppShell?

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
        let start = {
            shell.start()
            if let link { shell.open(link) }
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

    /// Universal links while the app is running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else { return }
        shell?.open(url)
    }
}
