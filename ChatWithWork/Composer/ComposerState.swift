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
        let iconName: String?
        let invertIcon: Bool?
    }

    struct PermissionModes: Decodable, Equatable, Sendable {
        struct Option: Decodable, Equatable, Sendable, Identifiable {
            let value: String
            let label: String
            let description: String?
            let selected: Bool
            let disabled: Bool
            var id: String { value }
        }
        let selected: String?
        let options: [Option]
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

    let overlay: Bool
    let visible: Bool
    let placeholder: String
    /// The words the web composer already holds (a shared link waiting, a
    /// restored draft), files left out.
    let text: String
    let locked: Bool
    let lockReason: String?
    let working: Bool
    let stopping: Bool
    let models: [Model]
    let permissionModes: PermissionModes?
    let webSearch: WebSearch?
    let dictation: Dictation?
    let csrfToken: String?
    let attachments: [Attachment]
    let acceptsFiles: Bool

    /// Recheck the latest page state when a sheet opened earlier returns a choice.
    func canSelectPermissionMode(_ value: String) -> Bool {
        !locked && permissionModes?.options.contains { $0.value == value && !$0.disabled } == true
    }

    var selectedModel: Model? { models.first(where: \.selected) }
    var isUploading: Bool { attachments.contains(where: \.uploading) }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        overlay = try values.decodeIfPresent(Bool.self, forKey: .overlay) ?? false
        visible = try values.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        placeholder = try values.decodeIfPresent(String.self, forKey: .placeholder) ?? ""
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        locked = try values.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        lockReason = try values.decodeIfPresent(String.self, forKey: .lockReason)
        working = try values.decodeIfPresent(Bool.self, forKey: .working) ?? false
        stopping = try values.decodeIfPresent(Bool.self, forKey: .stopping) ?? false
        models = try values.decodeIfPresent([Model].self, forKey: .models) ?? []
        permissionModes = try values.decodeIfPresent(PermissionModes.self, forKey: .permissionModes)
        webSearch = try values.decodeIfPresent(WebSearch.self, forKey: .webSearch)
        dictation = try values.decodeIfPresent(Dictation.self, forKey: .dictation)
        csrfToken = try values.decodeIfPresent(String.self, forKey: .csrfToken)
        attachments = try values.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        acceptsFiles = try values.decodeIfPresent(Bool.self, forKey: .acceptsFiles) ?? !locked
    }

    private enum CodingKeys: String, CodingKey {
        case overlay, visible, placeholder, text, locked, lockReason, working, stopping, models, permissionModes, webSearch, dictation, csrfToken, attachments, acceptsFiles
    }

    /// Whether Send can go now: words or files, nothing still uploading, and
    /// not locked. While an answer works, Send steers it (the web decides).
    func canSend(text: String) -> Bool {
        !locked && !isUploading && hasContent(text: text)
    }

    /// Which of Stop and Send the composer shows for these words. Not
    /// working: Send alone. Working with an empty field: Stop alone. Working
    /// with words or files: Stop beside Send, which steers. Stop holds while
    /// the answer is stopping.
    struct Buttons: Equatable, Sendable {
        let stop: Bool
        let stopEnabled: Bool
        let send: Bool
        let sendEnabled: Bool
    }

    func buttons(text: String) -> Buttons {
        let stop = working
        let send = !working || hasContent(text: text)
        return Buttons(stop: stop, stopEnabled: stop && !stopping, send: send, sendEnabled: send && canSend(text: text))
    }

    private func hasContent(text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
}

/// What the app tells the web composer, as a reply to its latest `connect`.
nonisolated enum ComposerAction: Encodable, Equatable, Sendable {
    case send(text: String)
    case stop
    case model(index: Int)
    case permissionMode(value: String)
    case webSearch(on: Bool)
    case attach(files: [ComposerFile])
    case remove(id: String)
    case text(String)
    case layout(height: Double, width: Double)

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
        case .permissionMode(let value):
            try values.encode("permissionMode", forKey: .action)
            try values.encode(value, forKey: .value)
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
        case .layout(let height, let width):
            try values.encode("layout", forKey: .action)
            try values.encode(height, forKey: .height)
            try values.encode(width, forKey: .width)
        }
    }

    private enum Key: String, CodingKey {
        case action, text, index, value, on, files, id, height, width
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
