import Foundation
import HotwireNative
import Testing
@testable import ChatWithWork

/// The composer's messages as the web sends them and the replies the app
/// sends back (docs/server-contract.md, "The composer").
@Suite("Composer")
struct ComposerTests {
    static let state = """
    {"placeholder":"Reply to Chat with Work","text":"Shared: https://example.com","locked":false,"lockReason":null,
     "working":true,"stopping":false,
     "models":[{"name":"Gemini 3.8 Flash","rate":"About 2 credits per answer","selected":true,"searchesWeb":true},
               {"name":"Qwen3.8-27B","rate":"Free","selected":false,"searchesWeb":false}],
     "webSearch":{"on":false,"disabled":false,"note":"Searches leave the EU."},
     "dictation":{"url":"/482139075/dictations"},"csrfToken":"abc",
     "attachments":[{"id":"7","name":"plan.pdf","size":"1.2 MB","contentType":"application/pdf","uploading":true,"progress":40}],
     "acceptsFiles":true,
     "metadata":{"url":"https://chatwithwork.com/482139075/chats/42"}}
    """

    private func message(_ event: String, _ json: String) -> Message {
        Message(id: "1", component: "composer", event: event, metadata: .init(url: "https://chatwithwork.com/482139075/chats/42"), jsonData: json)
    }

    @Test("reads the web composer's state")
    func decodes() throws {
        let state: ComposerState? = message("connect", Self.state).data()
        let decoded = try #require(state)
        #expect(decoded.text == "Shared: https://example.com")
        #expect(decoded.working)
        #expect(decoded.selectedModel?.name == "Gemini 3.8 Flash")
        #expect(decoded.webSearch?.note == "Searches leave the EU.")
        #expect(decoded.dictation?.url == "/482139075/dictations")
        #expect(decoded.attachments.first?.uploading == true)
        #expect(decoded.isUploading)
    }

    @Test("reads a state that leaves out what it doesn't have")
    func minimal() {
        let state: ComposerState? = message("state", #"{"placeholder":"Ask anything","locked":true,"lockReason":"Out of credits"}"#).data()
        #expect(state?.locked == true)
        #expect(state?.models.isEmpty == true)
        #expect(state?.webSearch == nil)
        #expect(state?.acceptsFiles == false)
        #expect(state?.text == "")
    }

    @Test("sends only words or files, nothing uploading, and never while locked")
    func canSend() throws {
        let uploading = try #require(message("connect", Self.state).data() as ComposerState?)
        #expect(!uploading.canSend(text: "hello"), "A file still uploading holds Send")

        let ready = try #require(message("connect", #"{"placeholder":"","attachments":[]}"#).data() as ComposerState?)
        #expect(ready.canSend(text: "hello"))
        #expect(!ready.canSend(text: "   "))

        let locked = try #require(message("connect", #"{"placeholder":"","locked":true}"#).data() as ComposerState?)
        #expect(!locked.canSend(text: "hello"))
    }

    @Test("replies with the contract's actions", arguments: [
        (ComposerAction.send(text: "Hi"), #"{"action":"send","text":"Hi"}"#),
        (.stop, #"{"action":"stop"}"#),
        (.model(index: 1), #"{"action":"model","index":1}"#),
        (.webSearch(on: true), #"{"action":"webSearch","on":true}"#),
        (.remove(id: "7"), #"{"action":"remove","id":"7"}"#),
        (.text("words"), #"{"action":"text","text":"words"}"#)
    ])
    func actions(action: ComposerAction, json: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = String(decoding: try encoder.encode(action), as: UTF8.self)
        let expected = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary
        let actual = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? NSDictionary
        #expect(actual == expected)
    }

    @Test("attaches files as base64 with their name and type")
    func attach() throws {
        let file = ComposerFile(name: "scan.pdf", type: "application/pdf", bytes: Data("%PDF".utf8))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ComposerAction.attach(files: [file]))) as? [String: Any]
        #expect(json?["action"] as? String == "attach")
        let files = json?["files"] as? [[String: String]]
        #expect(files?.first?["data"] == Data("%PDF".utf8).base64EncodedString())
        #expect(files?.first?["type"] == "application/pdf")
    }
}
