import Foundation

/// What the web composer is right now, as the `composer` bridge component
/// sends it on `connect` and `state` (docs/server-contract.md, "The
/// composer"). The web one stays in the page, hidden, and keeps every rule:
/// locks, steering, the queue, files waiting for their scan, the model and
/// web search. The app draws it and tells it what the person did.
nonisolated struct ComposerState: Decodable, Equatable, Sendable {
    struct Model: Decodable, Equatable, Sendable {
        let name: String
        let rate: String?
        let selected: Bool
        let searchesWeb: Bool?
    }

    struct WebSearch: Decodable, Equatable, Sendable {
        let on: Bool
        let disabled: Bool
        let note: String?
    }

    struct Dictation: Decodable, Equatable, Sendable {
        let url: String
    }

    struct Attachment: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let size: String?
        let contentType: String?
        let uploading: Bool
        let progress: Double?
    }

    let placeholder: String
    /// The words the web composer already holds (a shared link waiting, a
    /// restored draft), files left out.
    let text: String
    let locked: Bool
    let lockReason: String?
    let working: Bool
    let stopping: Bool
    let models: [Model]
    let webSearch: WebSearch?
    let dictation: Dictation?
    let csrfToken: String?
    let attachments: [Attachment]
    let acceptsFiles: Bool

    var selectedModel: Model? { models.first(where: \.selected) }
    var isUploading: Bool { attachments.contains(where: \.uploading) }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        placeholder = try values.decodeIfPresent(String.self, forKey: .placeholder) ?? ""
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        locked = try values.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        lockReason = try values.decodeIfPresent(String.self, forKey: .lockReason)
        working = try values.decodeIfPresent(Bool.self, forKey: .working) ?? false
        stopping = try values.decodeIfPresent(Bool.self, forKey: .stopping) ?? false
        models = try values.decodeIfPresent([Model].self, forKey: .models) ?? []
        webSearch = try values.decodeIfPresent(WebSearch.self, forKey: .webSearch)
        dictation = try values.decodeIfPresent(Dictation.self, forKey: .dictation)
        csrfToken = try values.decodeIfPresent(String.self, forKey: .csrfToken)
        attachments = try values.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        acceptsFiles = try values.decodeIfPresent(Bool.self, forKey: .acceptsFiles) ?? !locked
    }

    private enum CodingKeys: String, CodingKey {
        case placeholder, text, locked, lockReason, working, stopping, models, webSearch, dictation, csrfToken, attachments, acceptsFiles
    }

    /// Whether Send can go now: words or files, nothing still uploading, and
    /// not locked. While an answer works, Send steers it (the web decides).
    func canSend(text: String) -> Bool {
        !locked && !isUploading && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }
}

/// What the app tells the web composer, as a reply to its latest `connect`.
nonisolated enum ComposerAction: Encodable, Equatable, Sendable {
    case send(text: String)
    case stop
    case model(index: Int)
    case webSearch(on: Bool)
    case attach(files: [ComposerFile])
    case remove(id: String)
    case text(String)

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .send(let text):
            try values.encode("send", forKey: .action)
            try values.encode(text, forKey: .text)
        case .stop:
            try values.encode("stop", forKey: .action)
        case .model(let index):
            try values.encode("model", forKey: .action)
            try values.encode(index, forKey: .index)
        case .webSearch(let on):
            try values.encode("webSearch", forKey: .action)
            try values.encode(on, forKey: .on)
        case .attach(let files):
            try values.encode("attach", forKey: .action)
            try values.encode(files, forKey: .files)
        case .remove(let id):
            try values.encode("remove", forKey: .action)
            try values.encode(id, forKey: .id)
        case .text(let text):
            try values.encode("text", forKey: .action)
            try values.encode(text, forKey: .text)
        }
    }

    private enum Key: String, CodingKey {
        case action, text, index, on, files, id
    }
}

/// A file for `attach`: its name, type, and bytes in base64.
nonisolated struct ComposerFile: Encodable, Equatable, Sendable {
    let name: String
    let type: String
    let data: String

    init(name: String, type: String, bytes: Data) {
        self.name = name
        self.type = type
        data = bytes.base64EncodedString()
    }
}
