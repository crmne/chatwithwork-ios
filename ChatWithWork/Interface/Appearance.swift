import UIKit

/// System chrome in Live Wire's colors. From iOS 26 the bars are Liquid
/// Glass, which picks up the canvas through the glass, so only the tint and
/// text are set there; earlier versions get a translucent canvas.
enum Appearance {
    static func configure() {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.tintColor = Palette.ink

        let tabBar = UITabBar.appearance()
        tabBar.tintColor = Palette.ink
        tabBar.unselectedItemTintColor = Palette.inkMuted

        UIRefreshControl.appearance().tintColor = Palette.inkMuted

        if #available(iOS 26.0, *) {
            return
        }

        let bar = UINavigationBarAppearance()
        bar.configureWithDefaultBackground()
        bar.backgroundColor = Palette.canvas.withAlphaComponent(0.82)
        bar.shadowColor = Palette.line
        bar.titleTextAttributes = [.foregroundColor: Palette.ink]
        bar.largeTitleTextAttributes = [.foregroundColor: Palette.ink]

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.titleTextAttributes = bar.titleTextAttributes
        edge.largeTitleTextAttributes = bar.largeTitleTextAttributes

        navigationBar.standardAppearance = bar
        navigationBar.compactAppearance = bar
        navigationBar.scrollEdgeAppearance = edge

        let tabs = UITabBarAppearance()
        tabs.configureWithDefaultBackground()
        tabs.backgroundColor = Palette.canvas.withAlphaComponent(0.82)
        tabs.shadowColor = Palette.line
        tabBar.standardAppearance = tabs
        tabBar.scrollEdgeAppearance = tabs
    }
}
