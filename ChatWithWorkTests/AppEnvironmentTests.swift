import Foundation
import Testing
@testable import ChatWithWork

@Suite("App environment")
struct AppEnvironmentTests {
    private func info(environment: String = "production", baseURL: String = "https://chatwithwork.com") -> [String: Any] {
        [
            "CWWEnvironment": environment,
            "CWWBaseURL": baseURL,
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "10200",
            "CFBundleIdentifier": "com.chatwithwork.app",
            "CWWCallbackScheme": "chatwithwork",
            "CWWPushEnvironment": "production"
        ]
    }

    private func defaults(_ values: [String: String] = [:]) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "AppEnvironmentTests.\(UUID().uuidString)")!
        values.forEach { defaults.set($1, forKey: $0) }
        return defaults
    }

    @Test("introduces itself with the user agent prefix the server parses")
    func userAgentPrefix() {
        let environment = AppEnvironment.load(info: info(), arguments: defaults(), variables: [:])
        #expect(environment.userAgentPrefix == "Chat with Work; platform=ios; version=1.2.0; build=10200;")
    }

    @Test("reads the server from Info.plist")
    func baseURLFromInfo() {
        let environment = AppEnvironment.load(info: info(environment: "staging", baseURL: "https://staging.chatwithwork.com"), arguments: defaults(), variables: [:])
        #expect(environment.name == .staging)
        #expect(environment.baseURL.absoluteString == "https://staging.chatwithwork.com")
        #expect(environment.remotePathConfigurationURL.absoluteString == "https://staging.chatwithwork.com/configurations/ios_v1.json")
    }

    @Test("lets development builds be pointed elsewhere at launch")
    func developmentOverrides() {
        let variable = AppEnvironment.load(
            info: info(environment: "development", baseURL: "https://chatwithwork.localhost"),
            arguments: defaults(),
            variables: ["CWW_BASE_URL": "http://192.168.1.20:3000"]
        )
        #expect(variable.baseURL.absoluteString == "http://192.168.1.20:3000")

        let argument = AppEnvironment.load(
            info: info(environment: "development", baseURL: "https://chatwithwork.localhost"),
            arguments: defaults(["CWWBaseURL": "https://staging.chatwithwork.com/"]),
            variables: ["CWW_BASE_URL": "http://192.168.1.20:3000"]
        )
        #expect(argument.baseURL.absoluteString == "https://staging.chatwithwork.com")
    }

    @Test("ignores overrides in production builds")
    func productionIgnoresOverrides() {
        let environment = AppEnvironment.load(
            info: info(),
            arguments: defaults(["CWWBaseURL": "https://example.com"]),
            variables: ["CWW_BASE_URL": "https://example.com"]
        )
        #expect(environment.baseURL.absoluteString == "https://chatwithwork.com")
    }

    @Test("accepts only http and https servers, without a path", arguments: [
        ("https://chatwithwork.com/", "https://chatwithwork.com"),
        ("https://chatwithwork.com/chats?x=1", "https://chatwithwork.com"),
        (" http://192.168.1.20:3000 ", "http://192.168.1.20:3000"),
        ("HTTPS://Staging.chatwithwork.com", "https://Staging.chatwithwork.com")
    ])
    func normalizesBaseURL(input: String, expected: String) {
        #expect(AppEnvironment.normalizedBaseURL(input)?.absoluteString == expected)
    }

    @Test("rejects anything that isn't a web server", arguments: ["chatwithwork.com", "ftp://chatwithwork.com", "https:", "javascript:alert(1)", ""])
    func rejectsBaseURL(input: String) {
        #expect(AppEnvironment.normalizedBaseURL(input) == nil)
    }

    @Test("builds URLs on its own server and recognizes them")
    func ownsItsURLs() {
        let environment = AppEnvironment.load(info: info(), arguments: defaults(), variables: [:])
        let chat = environment.url(path: "/482139075/chats/42?x=1")
        #expect(chat.absoluteString == "https://chatwithwork.com/482139075/chats/42?x=1")
        #expect(environment.owns(chat))
        #expect(!environment.owns(URL(string: "https://accounts.google.com/o/oauth2")!))
        #expect(!environment.owns(URL(string: "chatwithwork://sign-ins/complete")!))
        #expect(!environment.owns(URL(string: "https://chatwithwork.com.evil.example/chats")!))
    }

    @Test("names the APNs gateway the server should use")
    func pushEnvironment() {
        #expect(AppEnvironment.PushEnvironment.development.apnsName == "sandbox")
        #expect(AppEnvironment.PushEnvironment.production.apnsName == "production")
    }
}
