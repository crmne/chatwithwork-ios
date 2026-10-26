import ActivityKit
import UIKit

/// Live Activities for answers that keep working while the person is
/// elsewhere: the organization, "Answering" and how long, never the chat's
/// title or anything from it. ActivityKit starts activities only while the
/// app is in front, and iOS shows them only once the person leaves it, so
/// the app starts one as soon as a chat's composer says its answer works,
/// registers the activity's push token with the server, which ends it when
/// the answer ends (`POST /:account/chats/:number/live_activity`), and ends
/// it itself whenever the composer says the answer is done.
@MainActor
final class LiveActivities {
    static let shared = LiveActivities()

    private let environment = AppEnvironment.current

    /// The organization's name, for the activity (the sidebar knows it).
    var organizationName: () -> String? = { SidebarShell.current?.store.data?.organization.name }

    /// The composer on `chatURL` changed.
    func noteState(_ state: ComposerState, chatURL: URL?) {
        guard let chatURL, case .chat = AppRoute(url: chatURL).kind else { return }
        let path = chatURL.path(percentEncoded: false)
        if state.working {
            start(for: path, csrfToken: state.csrfToken)
        } else {
            end(for: path)
        }
    }

    // MARK: Starting and ending

    private func start(for path: String, csrfToken: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              !Activity<ChatActivityAttributes>.activities.contains(where: { $0.attributes.path == path })
        else { return }

        let attributes = ChatActivityAttributes(organization: organizationName() ?? "Chat with Work", path: path, startedAt: Date())
        let content = ActivityContent(state: ChatActivityAttributes.ContentState.answering, staleDate: Date().addingTimeInterval(60 * 60))
        let activity: Activity<ChatActivityAttributes>
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
        } catch {
            let error = error as NSError
            NSLog("Live Activity didn't start: %@ %ld", error.domain, error.code)
            return
        }

        Task { [environment] in
            for await token in activity.pushTokenUpdates {
                let hex = token.map { String(format: "%02x", $0) }.joined()
                await Self.register(hex, for: path, csrfToken: csrfToken, environment: environment)
            }
        }
    }

    private func end(for path: String) {
        Task {
            for activity in Activity<ChatActivityAttributes>.activities where activity.attributes.path == path {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Tells the server the activity's push token, so it can end it.
    private static func register(_ token: String, for path: String, csrfToken: String?, environment: AppEnvironment) async {
        let route = AppRoute(path: path)
        guard let account = route.account, case .chat(let number) = route.kind else { return }

        var request = URLRequest(url: environment.url(path: "/\(account.rawValue)/chats/\(number)/live_activity"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let csrfToken { request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token") }
        let body: [String: Any] = ["live_activity": ["token": token, "app_id": environment.bundleIdentifier, "environment": environment.pushEnvironment.apnsName]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        await WebSession.authorize(&request)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        // Without the token the server can't end the activity once the app is in the
        // background, so a failed request (offline, a server error) is tried again, waiting
        // longer each time. The server refusing it (4xx) won't change by trying again.
        for attempt in 0..<6 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(2 << attempt)) }
            guard let (_, response) = try? await session.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else { continue }
            if status < 500 { return }
        }
    }
}
