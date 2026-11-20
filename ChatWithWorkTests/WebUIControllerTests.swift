import Foundation
import Testing
import WebKit
@testable import ChatWithWork

/// The page's microphone, for the web composer's dictation: only this
/// server's own pages in the main frame get it, never the camera.
@Suite("Web UI delegate")
struct WebUIControllerTests {
    private let hosted = URL(string: "https://chatwithwork.com")!
    private let local = URL(string: "http://localhost:3351")!

    @Test("grants the microphone to the server's own page in the main frame")
    func grants() {
        #expect(WebUIController.decision(scheme: "https", host: "chatwithwork.com", port: 0, isMainFrame: true, type: .microphone, server: hosted) == .grant)
        #expect(WebUIController.decision(scheme: "http", host: "localhost", port: 3351, isMainFrame: true, type: .microphone, server: local) == .grant)
    }

    @Test("refuses the camera, frames, other origins, schemes and ports")
    func refuses() {
        #expect(WebUIController.decision(scheme: "https", host: "chatwithwork.com", port: 0, isMainFrame: true, type: .camera, server: hosted) == .deny)
        #expect(WebUIController.decision(scheme: "https", host: "chatwithwork.com", port: 0, isMainFrame: true, type: .cameraAndMicrophone, server: hosted) == .deny)
        #expect(WebUIController.decision(scheme: "https", host: "chatwithwork.com", port: 0, isMainFrame: false, type: .microphone, server: hosted) == .deny)
        #expect(WebUIController.decision(scheme: "https", host: "evil.example", port: 0, isMainFrame: true, type: .microphone, server: hosted) == .deny)
        #expect(WebUIController.decision(scheme: "http", host: "chatwithwork.com", port: 0, isMainFrame: true, type: .microphone, server: hosted) == .deny)
        #expect(WebUIController.decision(scheme: "http", host: "localhost", port: 3000, isMainFrame: true, type: .microphone, server: local) == .deny)
    }
}
