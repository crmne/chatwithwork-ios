import AppIntents
import Foundation
import HotwireNative
import Testing
import UIKit
@testable import ChatWithWork

/// New chat, New bot and Decisions from outside the app: which page each opens
/// and how it reaches the shell.
@Suite("Shortcuts", .serialized)
@MainActor
struct ShortcutsTests {
    private let account = AccountSlug("482139075")

    @Test("each opens its page in the organization on screen")
    func pagesInAnOrganization() {
        #expect(Shortcut.newChat.path(in: account) == "/482139075/chats/new")
        #expect(Shortcut.newBot.path(in: account) == "/482139075/bots/new")
        #expect(Shortcut.decisions.path(in: account) == "/482139075/decisions")
    }

    @Test("with no organization yet, the server's redirect picks the one used last")
    func pagesWithoutAnOrganization() {
        #expect(Shortcut.newChat.path(in: nil) == "/chats/new")
        #expect(Shortcut.newBot.path(in: nil) == "/bots/new")
        #expect(Shortcut.decisions.path(in: nil) == "/decisions")
    }

    @Test("New bot starts in the list the sidebar chose")
    func newBotInTheChosenList() {
        let chosen = "/482139075/bots/new?project_id=7"
        #expect(Shortcut.newBot.path(in: account, chosen: chosen) == chosen)
    }

    @Test("the path configuration opens them as the app's own New chat, New bot and Decisions")
    func presentations() throws {
        let configuration = PathConfiguration(sources: [.file(Bundle.main.url(forResource: "path-configuration", withExtension: "json")!)])
        let base = URL(string: "https://chatwithwork.com")!
        let properties = { (path: String) in configuration.properties(for: base.appending(path: path)) }
        #expect(properties(Shortcut.newChat.path(in: account))["presentation"] as? String == "replace_root")
        #expect(properties(Shortcut.decisions.path(in: account))["presentation"] as? String == "replace_root")
        #expect(properties(Shortcut.newBot.path(in: account))["context"] as? String == "modal")
    }

    @Test("the quick actions in Info.plist are the three shortcuts, by the names on Android")
    func quickActions() throws {
        let items = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: String]])
        #expect(items.map { $0["UIApplicationShortcutItemType"] } == Shortcut.allCases.map(\.rawValue))
        #expect(items.map { $0["UIApplicationShortcutItemTitle"] } == ["New chat", "New bot", "Decisions"])
        #expect(items[0]["UIApplicationShortcutItemIconSymbolName"] == "square.and.pencil")
        #expect(items[1]["UIApplicationShortcutItemIconFile"] == "ShortcutBot")
        #expect(UIImage(named: "ShortcutBot") != nil)
        #expect(items[2]["UIApplicationShortcutItemIconSymbolName"] == "checklist")
    }

    @Test("the App Shortcuts are the same three, and each opens the app")
    func appShortcuts() {
        #expect(ChatWithWorkShortcuts.appShortcuts.count == 3)
        #expect(NewChatIntent.openAppWhenRun)
        #expect(NewBotIntent.openAppWhenRun)
        #expect(DecisionsIntent.openAppWhenRun)
        #expect(String(localized: NewChatIntent.title) == "New chat")
        #expect(String(localized: NewBotIntent.title) == "New bot")
        #expect(String(localized: DecisionsIntent.title) == "Decisions")
    }

    @Test("an intent waits for the scene, then reaches its shell")
    func intentsReachTheShell() async throws {
        defer { ShortcutInbox.receiver = nil }
        ShortcutInbox.receiver = nil

        _ = try await DecisionsIntent().perform()
        var received: [Shortcut] = []
        ShortcutInbox.receiver = { received.append($0) }
        #expect(received == [.decisions])

        _ = try await NewChatIntent().perform()
        _ = try await NewBotIntent().perform()
        #expect(received == [.decisions, .newChat, .newBot])
        #expect(ShortcutInbox.take() == nil)
    }

    @Test("one that launched the app is the scene's to start on")
    func aColdLaunchTakesIt() async throws {
        ShortcutInbox.receiver = nil
        _ = try await NewBotIntent().perform()
        #expect(ShortcutInbox.take() == .newBot)
        #expect(ShortcutInbox.take() == nil)
    }
}
