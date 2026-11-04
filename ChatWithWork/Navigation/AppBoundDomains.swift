import Foundation
import WebKit

/// The web views keep to the app-bound domains (`WKAppBoundDomains` in
/// Info.plist): WebKit runs a page's service worker only there, and only in a
/// web view that limits its navigations to them, so this is what lets the
/// server's worker keep opened chats readable offline (the Rails app's
/// docs/offline-chats.md, "The phone apps").
///
/// Limited, a web view refuses to load a page of another site in its main
/// frame. Nothing needs to: links to other sites already leave through the
/// router (Safari's sheet, or the system for other schemes), provider
/// sign-ins through ASWebAuthenticationSession, and Turbo's cross-origin
/// redirects through the same router. Frames of other sites (MCP Apps on
/// chatwithwork-apps.com) and their assets (the CDN) still load. The
/// bridge's scripts run on bound domains only, where the app's pages are.
///
/// A build pointed at a server outside the list (a computer on the network,
/// see Config/Local.xcconfig.example) doesn't limit, so it still loads, but
/// gets no worker.
nonisolated enum AppBoundDomains {
    static let declared: [String] = Bundle.main.object(forInfoDictionaryKey: "WKAppBoundDomains") as? [String] ?? []

    /// Whether `url`'s host is one of `declared`, or under one of them, as
    /// WebKit matches them: web views pointed at a server it covers limit
    /// their navigations to the declared domains.
    static func covers(_ url: URL, declared: [String] = declared) -> Bool {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return false }
        return declared.contains { domain in
            let domain = domain.lowercased()
            return !domain.isEmpty && (host == domain || host.hasSuffix("." + domain))
        }
    }

    /// Keeps the web views' data, where the worker's encrypted copies of
    /// chats live (IndexedDB and Cache Storage under Library/WebKit), out of
    /// iCloud and computer backups, so they never leave the phone.
    static func excludeWebDataFromBackup(fileManager: FileManager = .default) {
        guard let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        var webKit = library.appending(path: "WebKit", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: webKit, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try webKit.setResourceValues(values)
        } catch {
            // Best effort: a backup that includes the data still holds only
            // encrypted copies under a key that stays in the browser's store.
        }
    }
}
