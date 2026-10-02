import HotwireNative
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let environment = AppEnvironment.current
        if LaunchOptions.isUnitTesting { return true }
        if LaunchOptions.resetsState { SessionMemory.standard.reset() }

        Appearance.configure()
        HotwireSetup.configure(for: environment)
        PushNotifications.shared.configure(environment: environment)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    // MARK: Remote notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotifications.shared.didFailToRegister(error: error)
    }
}

/// Switches for development and UI tests, read from launch arguments.
enum LaunchOptions {
    /// Unit tests run inside the app; it stays idle for them rather than
    /// starting the shell and reaching for a server.
    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `-CWWResetState YES` starts as a fresh install would: no session
    /// cookie, no remembered sign-in or organization.
    static var resetsState: Bool { UserDefaults.standard.bool(forKey: "CWWResetState") }

    /// `-CWWAssumeSignedIn YES` starts in the tab shell, as after a sign-in.
    static var assumesSignedIn: Bool { UserDefaults.standard.bool(forKey: "CWWAssumeSignedIn") }

    /// `-CWWStartTab projects` starts on another tab (development builds).
    static var startTab: AppTab? {
        #if DEBUG
            UserDefaults.standard.string(forKey: "CWWStartTab").flatMap(AppTab.init(rawValue:))
        #else
            nil
        #endif
    }

    /// `-CWWToastSeconds 10` keeps notices up that long (development builds).
    /// UI tests wait for the app to settle before they look, which can take
    /// longer than a short notice lasts.
    static var toastSeconds: Double? {
        #if DEBUG
            let seconds = UserDefaults.standard.double(forKey: "CWWToastSeconds")
            return seconds > 0 ? seconds : nil
        #else
            nil
        #endif
    }
}
