import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

@MainActor
@Suite("Dictation lifetime")
struct DictationTests {
    @Test func cancelledTranscriptCannotChangeTheDraft() async throws {
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/1000001/chats/1")!)
        let composer = ComposerController.on(screen)
        let state = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"dictation":{"url":"/1000001/dictations"}}"#.utf8))
        composer.update(state, connected: true)
        composer.view.textView.text = "Keep my draft"
        let pending = PendingTranscript()
        composer.transcribeRecording = { _, _, _, _ in await pending.words() }
        var sent: [ComposerAction] = []
        composer.send = { sent.append($0) }
        let task = composer.transcribe(URL(fileURLWithPath: "/synthetic.m4a"), at: "/dictations", state: state)
        await pending.waitUntilStarted()
        composer.view.onCancelDictating?()
        pending.finish("This arrived too late")
        await task.value
        #expect(composer.view.textView.text == "Keep my draft")
        #expect(composer.view.mode == .typing)
        #expect(sent.isEmpty)
    }

    @Test func olderTranscriptCannotFinishANewerSession() async throws {
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/1000001/chats/1")!)
        let composer = ComposerController.on(screen)
        let state = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"dictation":{"url":"/1000001/dictations"}}"#.utf8))
        composer.update(state, connected: true)
        let first = PendingTranscript()
        let second = PendingTranscript()
        composer.transcribeRecording = { _, _, _, _ in await first.words() }
        let old = composer.transcribe(URL(fileURLWithPath: "/first.m4a"), at: "/dictations", state: state)
        await first.waitUntilStarted()
        composer.view.onCancelDictating?()
        composer.transcribeRecording = { _, _, _, _ in await second.words() }
        let current = composer.transcribe(URL(fileURLWithPath: "/second.m4a"), at: "/dictations", state: state)
        await second.waitUntilStarted()
        first.finish("Old words")
        await old.value
        #expect(composer.view.mode == .transcribing)
        #expect(composer.view.textView.text.isEmpty)
        second.finish("Current words")
        await current.value
        #expect(composer.view.mode == .typing)
        #expect(composer.view.textView.text == "Current words")
    }

    @Test func silenceAndClicksAreNotSpeech() {
        var meter = SpeechActivity()
        #expect(meter.canTranscribe, "Unavailable metering must not discard speech")
        meter.observe(level: 0, at: 0)
        meter.observe(level: 0.5, at: 0.1)
        meter.observe(level: 0, at: 0.2)
        meter.observe(level: 0.04, at: 0.4)
        meter.observe(level: 0.04, at: 0.6)
        #expect(!meter.canTranscribe)
        meter.observe(level: 0.04, at: 0.8)
        #expect(meter.canTranscribe)
        meter.observe(level: 0, at: 1)
        #expect(meter.canTranscribe, "Pausing after speech must keep the recording")
    }
}

@MainActor
private final class PendingTranscript {
    private var continuation: CheckedContinuation<String, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func words() async -> String {
        await withCheckedContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation == nil { await withCheckedContinuation { started = $0 } }
    }

    func finish(_ words: String) { continuation?.resume(returning: words) }
}
