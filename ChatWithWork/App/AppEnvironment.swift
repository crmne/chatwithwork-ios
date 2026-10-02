import Foundation

/// Where this build points and how it introduces itself to the server.
///
/// The base URL comes from the build configuration (`CWW_BASE_URL` in
/// `Config/*.xcconfig`, written into Info.plist). Development and staging
/// builds can be pointed elsewhere at launch, which production builds ignore:
///
///     xcrun simctl launch booted com.chatwithwork.app.debug -CWWBaseURL https://staging.chatwithwork.com
///
/// or with the `CWW_BASE_URL` environment variable in the Xcode scheme.
nonisolated struct AppEnvironment: Sendable, Equatable {
    enum Name: String, Sendable {
        case development
        case staging
        case production
    }

    let name: Name
    let baseURL: URL
    let version: String
    let build: String
    let bundleIdentifier: String
    let callbackScheme: String
    let pushEnvironment: PushEnvironment

    enum PushEnvironment: String, Sendable {
        case development
        case production

        /// The name APNs gives the environment, which the server needs to
        /// pick the right gateway.
        var apnsName: String {
            switch self {
            case .development: "sandbox"
            case .production: "production"
            }
        }
    }

    /// The prefix Hotwire Native puts before its own tokens. Rails reads it
    /// to tell the app apart from a browser and to know which build it is
    /// talking to. The format is part of the server contract and matches the
    /// Android app's, with `platform=android` there.
    var userAgentPrefix: String {
        "Chat with Work; platform=ios; version=\(version); build=\(build);"
    }

    var isProduction: Bool { name == .production }

    /// The bundled path configuration, overridden by the server's copy.
    var remotePathConfigurationURL: URL {
        url(path: "/configurations/ios_v1.json")
    }

    /// An absolute URL on this server for `path`, which may carry a query.
    func url(path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    /// Whether `url` belongs to this server (same scheme family and host).
    func owns(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host()?.lowercased() == baseURL.host()?.lowercased() && url.port == baseURL.port
    }
}

nonisolated extension AppEnvironment {
    static let current: AppEnvironment = load(
        info: Bundle.main.infoDictionary ?? [:],
        arguments: UserDefaults.standard,
        variables: ProcessInfo.processInfo.environment
    )

    /// Builds the environment from Info.plist, letting launch arguments and
    /// environment variables point non-production builds elsewhere.
    static func load(info: [String: Any], arguments: UserDefaults, variables: [String: String]) -> AppEnvironment {
        let name = (info["CWWEnvironment"] as? String).flatMap(Name.init(rawValue:)) ?? .production
        let configured = (info["CWWBaseURL"] as? String).flatMap(normalizedBaseURL) ?? URL(string: "https://chatwithwork.com")!

        var baseURL = configured
        if name != .production {
            if let override = variables["CWW_BASE_URL"].flatMap(normalizedBaseURL) {
                baseURL = override
            }
            if let override = arguments.string(forKey: "CWWBaseURL").flatMap(normalizedBaseURL) {
                baseURL = override
            }
        }

        return AppEnvironment(
            name: name,
            baseURL: baseURL,
            version: info["CFBundleShortVersionString"] as? String ?? "0.0.0",
            build: info["CFBundleVersion"] as? String ?? "0",
            bundleIdentifier: info["CFBundleIdentifier"] as? String ?? "com.chatwithwork.app",
            callbackScheme: info["CWWCallbackScheme"] as? String ?? "chatwithwork",
            pushEnvironment: (info["CWWPushEnvironment"] as? String).flatMap(PushEnvironment.init(rawValue:)) ?? .production
        )
    }

    /// Accepts `https://host[:port]` (or `http` for local development) and
    /// drops any path, so URLs are always built from the server's root.
    static func normalizedBaseURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
