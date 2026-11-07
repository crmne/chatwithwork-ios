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

    // On November 7, 2026 the proxy in front of the app answered three dictations with a page of its own after 30
    // seconds, and each recording was lost.
    @Test func aRecordingThatCouldNotBeTranscribedIsKeptToSendAgain() async throws {
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/1000001/chats/1")!)
        let composer = ComposerController.on(screen)
        let state = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"dictation":{"url":"/1000001/dictations"}}"#.utf8))
        composer.update(state, connected: true)
        composer.view.textView.text = "Compare the Q3 budget"
        let file = try syntheticRecording()
        composer.transcribeRecording = { _, _, _, _ in throw DictationRecorder.Failure.from(status: 504, error: nil) }

        await composer.transcribe(file, at: "/dictations", state: state).value
        #expect(composer.view.mode == .failed("Couldn't transcribe."))
        #expect(composer.view.textView.text == "Compare the Q3 budget")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(composer.keptRecording?.file == file)

        var sent: [URL] = []
        composer.transcribeRecording = { url, _, _, _ in sent.append(url); return "And the Q4 forecast." }
        await composer.retryDictating()?.value
        #expect(sent == [file])
        #expect(composer.view.mode == .typing)
        #expect(composer.view.textView.text.hasSuffix("And the Q4 forecast."))
        #expect(composer.view.textView.text.hasPrefix("Compare the Q3 budget"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(composer.keptRecording == nil)
    }

    @Test func discardThrowsAKeptRecordingAway() async throws {
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/1000001/chats/1")!)
        let composer = ComposerController.on(screen)
        let state = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"dictation":{"url":"/1000001/dictations"}}"#.utf8))
        composer.update(state, connected: true)
        let file = try syntheticRecording()
        composer.transcribeRecording = { _, _, _, _ in throw DictationRecorder.Failure.refused("Couldn't transcribe that. Try again in a moment.") }

        await composer.transcribe(file, at: "/dictations", state: state).value
        #expect(composer.view.mode == .failed("Couldn't transcribe that. Try again in a moment."))
        composer.view.onCancelDictating?()
        #expect(composer.view.mode == .typing)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(composer.keptRecording == nil)
    }

    @Test func aRecordingTheServerRefusesForItselfIsNotKept() async throws {
        let screen = WebScreen.make(url: URL(string: "https://chatwithwork.com/1000001/chats/1")!)
        let composer = ComposerController.on(screen)
        let state = try JSONDecoder().decode(ComposerState.self, from: Data(#"{"dictation":{"url":"/1000001/dictations"}}"#.utf8))
        composer.update(state, connected: true)
        let file = try syntheticRecording()
        composer.transcribeRecording = { _, _, _, _ in
            throw DictationRecorder.Failure.from(status: 415, error: "That recording is in a format we can't transcribe.")
        }

        await composer.transcribe(file, at: "/dictations", state: state).value
        #expect(composer.view.mode == .typing)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func onlyTheAppsOwnRefusalOfTheRecordingDropsIt() {
        #expect(DictationRecorder.Failure.from(status: 504, error: nil).keepsRecording)
        #expect(DictationRecorder.Failure.from(status: 415, error: nil).keepsRecording, "a proxy's own page")
        #expect(DictationRecorder.Failure.from(status: 502, error: "Couldn't transcribe that.").keepsRecording)
        #expect(DictationRecorder.Failure.from(status: 403, error: "Out of credits.").keepsRecording)
        for status in [400, 413, 415] {
            #expect(!DictationRecorder.Failure.from(status: status, error: "No.").keepsRecording)
        }
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

private func syntheticRecording() throws -> URL {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-test-\(UUID().uuidString).m4a")
    try Data([1, 2, 3]).write(to: file)
    return file
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
