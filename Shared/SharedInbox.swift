import Foundation

/// A file shared into the app from the share sheet.
nonisolated struct SharedFile: Equatable, Sendable {
    let name: String
    let type: String
    let data: Data
}

/// Files the share extension hands to the app, in the app group's container:
/// one folder per share, named in the `shared` parameter of the
/// `chatwithwork://new-chat` link, which the app reads once and deletes.
///
/// The extension copies each file into the folder as it arrives, never
/// holding them in memory: share extensions are killed past about 120 MB,
/// and a share may carry ten files of up to 25 MB.
nonisolated enum SharedInbox {
    /// The most one file may be (the app passes it to the page as base64).
    static let largest = 25 * 1024 * 1024

    /// One file kept in a share's folder: what it was called, its type, and
    /// the name it's kept under.
    struct Entry: Codable, Equatable, Sendable {
        let name: String
        let type: String
        let file: String
    }

    /// A share's folder while the extension fills it.
    struct Share: Sendable {
        let name: String
        let folder: URL
    }

    private static let manifest = "files.json"

    static var groupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "CWWAppGroup") as? String
    }

    /// Where shares are kept: the app group's container, unless `root` says otherwise (tests).
    private static func inbox(_ root: URL?) -> URL? {
        if let root { return root }
        guard let group = groupIdentifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appendingPathComponent("Shared", isDirectory: true)
    }

    /// A new, empty folder for one share.
    static func begin(in root: URL? = nil) -> Share? {
        guard let inbox = inbox(root) else { return nil }
        prune(inbox)
        let name = UUID().uuidString
        let folder = inbox.appendingPathComponent(name, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        return Share(name: name, folder: folder)
    }

    /// Removes shares the app never took (the link didn't open it), a day on.
    private static func prune(_ inbox: URL, olderThan age: TimeInterval = 24 * 60 * 60) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let cutoff = Date().addingTimeInterval(-age)
        for folder in folders where ((try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) < cutoff {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// Copies the file at `url` into the share as its `index`th file, unless
    /// it's larger than `largest`.
    static func keep(_ url: URL, name: String, type: String, index: Int, in share: Share) -> Entry? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        guard size <= largest else { return nil }
        let file = String(index)
        guard (try? FileManager.default.copyItem(at: url, to: share.folder.appendingPathComponent(file))) != nil else { return nil }
        return Entry(name: name, type: type, file: file)
    }

    /// Writes down what the share holds and returns its name for the link,
    /// or nil (and nothing kept) when it holds nothing.
    static func finish(_ share: Share, entries: [Entry]) -> String? {
        guard !entries.isEmpty,
              let data = try? JSONEncoder().encode(entries),
              (try? data.write(to: share.folder.appendingPathComponent(manifest))) != nil
        else {
            try? FileManager.default.removeItem(at: share.folder)
            return nil
        }
        return share.name
    }

    /// The files kept under `name`, removed as they're read.
    static func take(_ name: String, in root: URL? = nil) -> [SharedFile] {
        guard UUID(uuidString: name) != nil, let inbox = inbox(root) else { return [] }
        let folder = inbox.appendingPathComponent(name, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(manifest)),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.compactMap { entry in
            guard Int(entry.file) != nil,
                  let bytes = try? Data(contentsOf: folder.appendingPathComponent(entry.file))
            else { return nil }
            return SharedFile(name: entry.name, type: entry.type, data: bytes)
        }
    }
}
