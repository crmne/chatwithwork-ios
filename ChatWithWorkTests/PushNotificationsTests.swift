import Foundation
import Testing
import UIKit
import UserNotifications
@testable import ChatWithWork

/// Tapping a notification, as iOS delivers it: through the Objective-C
/// delegate method with a completion handler, on the main thread.
///
/// Build 100 crashed on every tap: its async delegate method ran off the main
/// thread and called UIKit's completion handler from there.
@Suite("Push notifications", .serialized)
@MainActor
struct PushNotificationsTests {
    private let push = PushNotifications.shared
    private let environment = AppEnvironment.current

    init() {
        push.onOpen = nil
        push.isShowing = nil
    }

    /// A notification iOS would deliver, with the server's payload.
    private func notification(path: String?) throws -> UNNotification {
        let content = UNMutableNotificationContent()
        content.title = "Acme"
        content.body = "A change is waiting for your approval in Slack."
        content.userInfo = ["kind": "approval_waiting"].merging(path.map { ["path": $0] } ?? [:]) { $1 }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        // UNNotification and UNNotificationResponse have no public
        // initializers; these are the class methods iOS itself uses.
        let made = (UNNotification.self as AnyObject)
            .perform(NSSelectorFromString("notificationWithRequest:date:"), with: request, with: Date())?
            .takeUnretainedValue() as? UNNotification
        return try #require(made)
    }

    private func response(path: String?) throws -> UNNotificationResponse {
        let made = (UNNotificationResponse.self as AnyObject)
            .perform(NSSelectorFromString("responseWithNotification:actionIdentifier:"), with: try notification(path: path), with: UNNotificationDefaultActionIdentifier)?
            .takeUnretainedValue() as? UNNotificationResponse
        return try #require(made)
    }

    /// Taps `response` the way iOS does and waits for the completion handler.
    private func tap(_ response: UNNotificationResponse) async -> Bool {
        let delegate: UNUserNotificationCenterDelegate = push
        return await withCheckedContinuation { continuation in
            delegate.userNotificationCenter?(.current(), didReceive: response) {
                continuation.resume(returning: Thread.isMainThread)
            }
        }
    }

    @Test("a tap opens the chat and finishes on the main thread")
    func tapOpensChat() async throws {
        var opened: [URL] = []
        push.onOpen = { opened.append($0) }

        let onMain = await tap(try response(path: "/482139075/chats/42"))

        #expect(onMain, "iOS's completion handler must be called on the main thread")
        #expect(opened == [environment.url(path: "/482139075/chats/42")])
    }

    @Test("a tap before the shell is ready waits for it (launched from the notification)")
    func coldLaunch() async throws {
        let onMain = await tap(try response(path: "/482139075/chats/42"))
        #expect(onMain)

        var opened: [URL] = []
        push.onOpen = { opened.append($0) }
        #expect(opened == [environment.url(path: "/482139075/chats/42")])

        // Only once: a shell built again doesn't reopen it.
        push.onOpen = { opened.append($0) }
        #expect(opened.count == 1)
    }

    @Test("a tap without a page of this server opens nothing", arguments: [nil, "", "chats/42", "//evil.example/chats/42", "https://evil.example/x"])
    func ignoresOtherPaths(path: String?) async throws {
        var opened: [URL] = []
        push.onOpen = { opened.append($0) }

        let onMain = await tap(try response(path: path))

        #expect(onMain)
        #expect(opened.isEmpty)
    }

    @Test("a notification about the page on screen stays quiet, others show")
    func presentsInForeground() async throws {
        push.isShowing = { $0.path() == "/482139075/chats/42" }
        let delegate: UNUserNotificationCenterDelegate = push

        func present(_ path: String) async throws -> (UNNotificationPresentationOptions, Bool) {
            let notification = try notification(path: path)
            return await withCheckedContinuation { continuation in
                delegate.userNotificationCenter?(.current(), willPresent: notification) { options in
                    continuation.resume(returning: (options, Thread.isMainThread))
                }
            }
        }

        let (same, sameOnMain) = try await present("/482139075/chats/42")
        let (other, otherOnMain) = try await present("/482139075/chats/7")
        #expect(same.isEmpty && sameOnMain)
        #expect(other.contains(.banner) && otherOnMain)
    }

    @Test("offers notifications once per install")
    func asksOnce() async {
        let defaults = UserDefaults(suiteName: "PushNotificationsTests")!
        defaults.removePersistentDomain(forName: "PushNotificationsTests")
        push.configure(environment: environment, defaults: defaults)
        defer { push.configure(environment: environment) }

        #expect(!push.hasAsked)
        push.hasAsked = true
        var presented = false
        await push.askOnceIfNeeded { presented = true; return nil }
        #expect(!presented, "Once asked, the app never asks again")
    }
}
