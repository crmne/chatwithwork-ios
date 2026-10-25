import Foundation

/// A file shared into the app from the share sheet.
nonisolated struct SharedFile: Codable, Equatable, Sendable {
    let name: String
    let type: String
    let data: Data
}

/// Files the share extension hands to the app, in the app group's container:
/// one folder per share, named in the `shared` parameter of the
/// `chatwithwork://new-chat` link, which the app reads once and deletes.
nonisolated enum SharedInbox {
    /// The most one file may be (the app passes it to the page as base64).
    static let largest = 25 * 1024 * 1024

    static var groupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "CWWAppGroup") as? String
    }

    private static var inbox: URL? {
        guard let group = groupIdentifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appendingPathComponent("Shared", isDirectory: true)
    }

    /// Keeps `files` and returns the folder's name, or nil when there are none.
    static func store(_ files: [SharedFile]) -> String? {
        guard !files.isEmpty, let inbox else { return nil }
        let name = UUID().uuidString
        let folder = inbox.appendingPathComponent(name, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              let data = try? JSONEncoder().encode(files),
              (try? data.write(to: folder.appendingPathComponent("files.json"))) != nil
        else { return nil }
        return name
    }

    /// The files kept under `name`, removed as they're read.
    static func take(_ name: String) -> [SharedFile] {
        guard UUID(uuidString: name) != nil, let inbox else { return [] }
        let folder = inbox.appendingPathComponent(name, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("files.json")) else { return [] }
        return (try? JSONDecoder().decode([SharedFile].self, from: data)) ?? []
    }
}
