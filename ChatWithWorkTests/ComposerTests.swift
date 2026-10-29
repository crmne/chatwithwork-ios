import Foundation
import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

/// The composer's messages as the web sends them and the replies the app
/// sends back (docs/server-contract.md, "The composer").
@Suite("Composer")
struct ComposerTests {
    static let state = """
    {"overlay":true,"placeholder":"Reply to Chat with Work","text":"Shared: https://example.com","locked":false,"lockReason":null,
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
        #expect(decoded.overlay)
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
        #expect(state?.overlay == false)
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

    private func state(_ json: String) throws -> ComposerState {
        try #require(message("state", json).data() as ComposerState?)
    }

    @Test("shows Send alone while nothing works")
    func idleButtons() throws {
        let idle = try state(#"{"placeholder":""}"#)
        #expect(idle.buttons(text: "") == .init(stop: false, stopEnabled: false, send: true, sendEnabled: false))
        #expect(idle.buttons(text: "hello") == .init(stop: false, stopEnabled: false, send: true, sendEnabled: true))
    }

    @Test("shows Stop alone while an answer works and the field is empty")
    func stopAlone() throws {
        let working = try state(#"{"placeholder":"","working":true}"#)
        #expect(working.buttons(text: "") == .init(stop: true, stopEnabled: true, send: false, sendEnabled: false))
        #expect(working.buttons(text: " \n ") == .init(stop: true, stopEnabled: true, send: false, sendEnabled: false), "Blank words are an empty field")
    }

    @Test("shows Stop beside Send once there are words or files to steer with")
    func stopAndSend() throws {
        let working = try state(#"{"placeholder":"","working":true}"#)
        #expect(working.buttons(text: "Shorter, please") == .init(stop: true, stopEnabled: true, send: true, sendEnabled: true))

        let withFile = try state(#"{"placeholder":"","working":true,"attachments":[{"id":"7","name":"plan.pdf","uploading":false}]}"#)
        #expect(withFile.buttons(text: "") == .init(stop: true, stopEnabled: true, send: true, sendEnabled: true))

        let uploading = try state(#"{"placeholder":"","working":true,"attachments":[{"id":"7","name":"plan.pdf","uploading":true,"progress":40}]}"#)
        #expect(uploading.buttons(text: "hi") == .init(stop: true, stopEnabled: true, send: true, sendEnabled: false), "Send waits for the upload; Stop doesn't")
    }

    @Test("holds Stop while the answer is stopping")
    func stopping() throws {
        let stopping = try state(#"{"placeholder":"","working":true,"stopping":true}"#)
        #expect(stopping.buttons(text: "") == .init(stop: true, stopEnabled: false, send: false, sendEnabled: false))
        #expect(stopping.buttons(text: "wait") == .init(stop: true, stopEnabled: false, send: true, sendEnabled: true))
    }

    @Test("replies with the contract's actions", arguments: [
        (ComposerAction.send(text: "Hi"), #"{"action":"send","text":"Hi"}"#),
        (.stop, #"{"action":"stop"}"#),
        (.model(index: 1), #"{"action":"model","index":1}"#),
        (.webSearch(on: true), #"{"action":"webSearch","on":true}"#),
        (.remove(id: "7"), #"{"action":"remove","id":"7"}"#),
        (.text("words"), #"{"action":"text","text":"words"}"#),
        (.layout(height: 122, width: 402), #"{"action":"layout","height":122,"width":402}"#)
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

    @Test("dictation takes the field's place while it listens and transcribes, and gives the words back")
    @MainActor
    func dictationTakesTheComposer() throws {
        let view = ComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        view.update(try #require(message("connect", Self.state).data()))
        let line = try #require(view.descendant("composer.dictation") as? DictationLine)
        #expect(!view.textView.isHidden && line.isHidden)

        view.setMode(.recording)
        #expect(view.textView.isHidden && !line.isHidden)
        #expect(line.accessibilityLabel == "Listening")
        #expect(line.accessibilityValue == "0 seconds")
        #expect(view.descendant("composer.cancelDictation")?.isHidden == false)
        #expect(view.descendant("composer.send")?.accessibilityLabel == "Stop recording")

        view.setMode(.transcribing)
        #expect(view.textView.isHidden && !line.isHidden)
        #expect(line.accessibilityLabel == "Transcribing")

        view.append("Draft the recap")
        view.setMode(.typing)
        #expect(!view.textView.isHidden && line.isHidden)
        #expect(view.textView.text == "Draft the recap")
        #expect(view.descendant("composer.cancelDictation")?.isHidden == true)
    }

    @Test("puts the microphone and the globe in the bar, and the globe switches web search")
    @MainActor
    func oneTapButtons() throws {
        let view = ComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        var sent: [ComposerAction] = []
        var dictated = 0
        view.onAction = { sent.append($0) }
        view.onDictate = { dictated += 1 }
        view.update(try #require(message("connect", Self.state).data()))

        let dictate = try #require(view.descendant("composer.dictate") as? UIButton)
        let globe = try #require(view.descendant("composer.webSearch") as? UIButton)
        #expect(!dictate.isHidden && dictate.isEnabled && dictate.accessibilityLabel == "Dictate")
        #expect(!globe.isHidden && globe.accessibilityLabel == "Search the web" && globe.accessibilityValue == "Off")
        dictate.sendActions(for: .primaryActionTriggered)
        globe.sendActions(for: .primaryActionTriggered)
        #expect(dictated == 1)
        #expect(sent == [.webSearch(on: true)])

        // Where the model can't search, the globe stays and does nothing.
        let off = Self.state.replacingOccurrences(of: #""disabled":false"#, with: #""disabled":true"#)
        view.update(try #require(message("state", off).data()))
        globe.sendActions(for: .primaryActionTriggered)
        #expect(sent == [.webSearch(on: true)])
        #expect(globe.accessibilityTraits.contains(.notEnabled))

        // Nor while the composer is locked, though the model could search.
        let locked = Self.state.replacingOccurrences(of: #""locked":false"#, with: #""locked":true"#)
        view.update(try #require(message("state", locked).data()))
        globe.sendActions(for: .primaryActionTriggered)
        #expect(sent == [.webSearch(on: true)])
        #expect(globe.accessibilityTraits.contains(.notEnabled))

        // Neither is drawn where the composer doesn't offer it, nor while dictating.
        let without = Self.state
            .replacingOccurrences(of: #""webSearch":{"on":false,"disabled":false,"note":"Searches leave the EU."}"#, with: #""webSearch":null"#)
            .replacingOccurrences(of: #""dictation":{"url":"/482139075/dictations"}"#, with: #""dictation":null"#)
        view.update(try #require(message("state", without).data()))
        #expect(dictate.isHidden && globe.isHidden)
        view.update(try #require(message("state", Self.state).data()))
        view.setMode(.transcribing)
        #expect(dictate.isHidden && globe.isHidden)
    }

    @Test("a flashed line stays through the page's next state, and a lock replaces it")
    @MainActor
    func flashOutlastsState() throws {
        let view = ComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        view.update(try #require(message("connect", Self.state).data()))
        let line = try #require(view.descendant("composer.lock") as? UILabel)
        view.flash("Searches leave the EU.")
        view.update(try #require(message("state", Self.state).data()))
        #expect(!line.isHidden && line.text == "Searches leave the EU.")

        let locked = Self.state
            .replacingOccurrences(of: #""locked":false"#, with: #""locked":true"#)
            .replacingOccurrences(of: #""lockReason":null"#, with: #""lockReason":"Out of credits""#)
        view.update(try #require(message("state", locked).data()))
        #expect(!line.isHidden && line.text == "Out of credits")
    }

    @Test("an earlier expiry cannot dismiss a later flash with the same words")
    @MainActor
    func repeatedFlash() throws {
        let view = ComposerView(frame: .zero)
        var expirations: [@MainActor @Sendable () -> Void] = []
        view.scheduleFlashExpiration = { expirations.append($0) }
        view.flash("Searches leave the EU.")
        view.flash("Searches leave the EU.")
        let line = try #require(view.descendant("composer.lock") as? UILabel)
        expirations[0]()
        #expect(!line.isHidden && line.text == "Searches leave the EU.")
        expirations[1]()
        #expect(line.isHidden)
    }

    @Test("the globe waits for the page's state before accepting another tap")
    @MainActor
    func webSearchWaitsForState() throws {
        let view = ComposerView(frame: .zero)
        var actions: [ComposerAction] = []
        view.onAction = { actions.append($0) }
        view.update(try #require(message("connect", Self.state).data()))
        let globe = try #require(view.descendant("composer.webSearch") as? UIButton)
        globe.sendActions(for: .primaryActionTriggered)
        globe.sendActions(for: .primaryActionTriggered)
        #expect(actions == [.webSearch(on: true)])
        #expect(!globe.isEnabled)
        let on = Self.state.replacingOccurrences(of: #""on":false"#, with: #""on":true"#)
        view.update(try #require(message("state", on).data()))
        #expect(globe.isEnabled && globe.accessibilityValue == "On")
        globe.sendActions(for: .primaryActionTriggered)
        #expect(actions == [.webSearch(on: true), .webSearch(on: false)])
    }

    @Test("dictation's clock reads as the web's, and in words for VoiceOver")
    func dictationClock() {
        #expect(DictationLine.clock(0) == "0:00")
        #expect(DictationLine.clock(7) == "0:07")
        #expect(DictationLine.clock(83) == "1:23")
        #expect(DictationLine.spokenDuration(7, locale: Locale(identifier: "en_US")) == "7 seconds")
        #expect(DictationLine.spokenDuration(83, locale: Locale(identifier: "en_US")) == "1 minute, 23 seconds")
    }
}

@MainActor
extension UIView {
    /// The first view under this one with that accessibility identifier.
    func descendant(_ identifier: String) -> UIView? {
        for subview in subviews {
            if subview.accessibilityIdentifier == identifier { return subview }
            if let found = subview.descendant(identifier) { return found }
        }
        return nil
    }
}

/// The composer's controls as UIKit lays them out at a phone's width.
@MainActor
@Suite("Composer layout")
struct ComposerLayoutTests {
    /// As the server draws it: while an answer works, the model picker has
    /// no options (chats/_model_picker, locked while answering), so no models.
    private func state(working: Bool) throws -> ComposerState {
        let models = working ? "[]" : """
        [{"name":"GPT-6 Luna","rate":"About 2 credits per answer","selected":true},
         {"name":"Qwen3.8-27B","rate":"Free","selected":false}]
        """
        let json = #"{"placeholder":"Reply to Chat with Work","working":\#(working),"models":\#(models)}"#
        return try JSONDecoder().decode(ComposerState.self, from: Data(json.utf8))
    }

    private func modelButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == "composer.model" { return button }
        for subview in view.subviews {
            if let found = modelButton(in: subview) { return found }
        }
        return nil
    }

    @Test("shows the model's name again once an answer ends")
    func modelNameAfterAnswer() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let composer = ComposerView()
        composer.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(composer)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.isHidden = false
        defer { window.isHidden = true }
        let button = try #require(modelButton(in: composer))

        for working in [false, true, false, true, false] {
            composer.update(try state(working: working))
            window.layoutIfNeeded()
        }

        #expect(!button.isHidden)
        let title = try #require(button.titleLabel)
        let needed = title.intrinsicContentSize.width
        #expect(needed > 0)
        #expect(title.bounds.width >= needed - 0.5, "The model's name shows in full, not as a chevron alone (\(title.bounds.width) of \(needed) pt)")
        #expect(button.bounds.width >= button.intrinsicContentSize.width - 0.5)
    }
}
