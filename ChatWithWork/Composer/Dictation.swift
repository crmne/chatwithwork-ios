@preconcurrency import AVFoundation
@preconcurrency import HotwireNative
import UIKit
import WebKit

/// Dictation, the app's own way: it records here (AAC in an .m4a, at most
/// five minutes) and posts the recording to the composer's `dictation.url`
/// with the web views' session, where the server transcribes it in the EU
/// for credits. Never the system's speech recognizers: they were unreliable,
/// and off the device they send audio to Apple (docs/server-contract.md,
/// "Dictation").
@MainActor
final class DictationRecorder: NSObject, AVAudioRecorderDelegate {
    static let longest: TimeInterval = 5 * 60

    enum Failure: Error, Equatable {
        case microphoneRefused
        case couldNotRecord
        /// The server's own words, like "Dictation uses credits, and your
        /// organization has none left."
        case refused(String)
        case unavailable
    }

    private var recorder: AVAudioRecorder?
    private var speech = SpeechActivity()
    private(set) var file: URL?
    /// Called when the five minutes run out.
    var onLimit: (() -> Void)?

    var isRecording: Bool { recorder?.isRecording == true }

    /// The microphone's level now, 0 to 1, for the meter.
    var level: Float {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        speech.observe(level: pow(10, power / 20), at: recorder.currentTime)
        return max(0, min(1, (power + 50) / 50))
    }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw Failure.microphoneRefused }
        try Task.checkCancellation()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { throw Failure.couldNotRecord }
        recorder.isMeteringEnabled = true
        recorder.delegate = self
        guard recorder.record(forDuration: Self.longest) else { throw Failure.couldNotRecord }

        speech = SpeechActivity()
        self.recorder = recorder
        file = url
    }

    /// Stops and returns the recording, if there is one worth sending.
    func stop() -> URL? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let file = self.file
        self.file = nil
        // A tap or measured silence must not be sent to a speech model.
        guard duration >= 0.5, speech.canTranscribe else {
            if let file { try? FileManager.default.removeItem(at: file) }
            return nil
        }
        return file
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            // The five minutes ran out (a stop of our own clears `recorder` first).
            if self.recorder === recorder { self.onLimit?() }
        }
    }

    // MARK: Transcribing

    /// Posts the recording as the multipart field `audio` and returns the
    /// words, or the server's reason for refusing.
    static func transcribe(_ file: URL, at path: String, csrfToken: String?, environment: AppEnvironment) async throws -> String {
        defer { try? FileManager.default.removeItem(at: file) }
        guard let audio = try? Data(contentsOf: file) else { throw Failure.couldNotRecord }

        let boundary = "cww-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"dictation.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: environment.url(path: path), timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let csrfToken { request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token") }
        try Task.checkCancellation()
        await WebSession.authorize(&request)
        try Task.checkCancellation()

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.upload(for: request, from: body), let http = response as? HTTPURLResponse else {
            throw Failure.unavailable
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if http.statusCode == 200, let text = json?["text"] as? String { return text }
        if let error = json?["error"] as? String, !error.isEmpty { throw Failure.refused(error) }
        throw Failure.unavailable
    }
}

/// Requests the app makes itself with the web views' session: their cookies
/// for this server and the app's user agent, never a token of its own.
enum WebSession {
    @MainActor
    static func authorize(_ request: inout URLRequest) async {
        guard let url = request.url, let host = url.host() else { return }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies().filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
        HTTPCookie.requestHeaderFields(with: cookies).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }

    /// What the web views send, so the server knows the app and its build.
    @MainActor
    static var userAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) \(Hotwire.config.userAgent)"
    }
}

/// Matches the web's conservative silence gate: sustained signal above 0.02
/// for 300 ms. If metering never ran, leave the decision to transcription.
struct SpeechActivity {
    private var started: TimeInterval?
    private var measured = false
    private var heard = false
    var canTranscribe: Bool { !measured || heard }

    mutating func observe(level: Float, at time: TimeInterval) {
        measured = true
        if level > 0.02 {
            if started == nil { started = time }
            if time - (started ?? time) >= 0.3 { heard = true }
        } else {
            started = nil
        }
    }
}
