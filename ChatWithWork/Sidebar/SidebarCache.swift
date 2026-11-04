import Foundation

/// The last sidebar each organization showed, as the server sent it, so a
/// launch with no connection still lists the chats: opening one then gets the
/// copy the pages' service worker kept, or its "isn't available offline" page
/// (the Rails app's docs/offline-chats.md).
///
/// One file per organization in Application Support, readable only while the
/// phone is unlocked, kept out of backups like the web views' copies, and
/// deleted on signing out. Only the first page of the list is kept.
nonisolated enum SidebarCache {
    static func load(_ account: AccountSlug, in folder: URL? = folder) -> SidebarData? {
        guard let file = file(account, in: folder), let body = try? Data(contentsOf: file) else { return nil }
        return try? SidebarData.decode(body)
    }

    static func save(_ body: Data, for account: AccountSlug, in folder: URL? = folder) {
        guard let folder, let file = file(account, in: folder) else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            var marked = folder
            try marked.setResourceValues(excluded)
            try body.write(to: file, options: [.atomic, .completeFileProtection])
        } catch {
            // Nothing kept: offline, the sidebar says it couldn't load.
        }
    }

    /// Forgets every organization's.
    static func clear(in folder: URL? = folder) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    static let folder: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appending(path: "Sidebar", directoryHint: .isDirectory)

    private static func file(_ account: AccountSlug, in folder: URL?) -> URL? {
        folder?.appending(path: "\(account.rawValue).json")
    }
}
