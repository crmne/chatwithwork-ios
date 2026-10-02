@preconcurrency import HotwireNative
import UIKit
import WebKit

/// Everything Hotwire Native needs before the first navigator is created.
enum HotwireSetup {
    static func configure(for environment: AppEnvironment) {
        Hotwire.config.applicationUserAgentPrefix = environment.userAgentPrefix
        Hotwire.config.backButtonDisplayMode = .minimal
        Hotwire.config.hideTabBarWhenPushed = true
        Hotwire.config.animateReplaceActions = true
        // Modals get a close button from AppNavigationController instead,
        // on the leading side where iOS puts it, leaving the trailing side to
        // the form component's submit button.
        Hotwire.config.showDoneButtonOnModals = false
        #if DEBUG
            Hotwire.config.debugLoggingEnabled = true
        #endif

        Hotwire.config.defaultViewController = { url in
            WebScreen.make(url: url)
        }
        Hotwire.config.defaultNavigationController = {
            AppNavigationController()
        }
        Hotwire.config.makeCustomWebView = { configuration in
            WebScreen.makeWebView(configuration: configuration)
        }
        Hotwire.config.makeCustomErrorView = { error, handler in
            NativeErrorView(error: error, handler: handler)
        }

        Hotwire.loadPathConfiguration(from: pathConfigurationSources(for: environment))
        Hotwire.registerBridgeComponents(BridgeRegistry.all)
        Hotwire.registerRouteDecisionHandlers([
            FileRouteDecisionHandler(),
            AppNavigationRouteDecisionHandler(),
            SafariViewControllerRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler()
        ])
    }

    /// The bundled rules first, so the app works offline and on first
    /// launch, then the server's copy, which replaces them once it loads.
    static func pathConfigurationSources(for environment: AppEnvironment) -> [PathConfiguration.Source] {
        var sources = [PathConfiguration.Source]()
        if let bundled = Bundle.main.url(forResource: "path-configuration", withExtension: "json") {
            sources.append(.file(bundled))
        }
        sources.append(.server(environment.remotePathConfigurationURL))
        return sources
    }
}
