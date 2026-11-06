import AppIntents
import UIKit

/// New chat, New bot and Decisions, from outside the app: App Shortcuts (the
/// Shortcuts app, Spotlight, the Action Button, Siri's phrases) and the Home
/// Screen's quick actions. Each only opens its page, through the routing every
/// other link takes (`AppShell`); none takes any words, so what a person says
/// reaches a model only through the composer.
nonisolated enum Shortcut: String, CaseIterable, Sendable {
    // `UIApplicationShortcutItemType` in Info.plist.
    case newChat = "new-chat"
    case newBot = "new-bot"
    case decisions

    /// The page in `account`, the organization on screen: `chosen` where the
    /// sidebar names one for its list, else the server's redirect into the
    /// organization the person used last.
    func path(in account: AccountSlug?, chosen: String? = nil) -> String {
        if let chosen { return chosen }
        return switch self {
        case .newChat: AppPath.path(AppPath.newChat, in: account)
        case .newBot: AppPath.path(AppPath.newBot, in: account)
        case .decisions: AppPath.path(AppPath.decisions, in: account)
        }
    }
}

/// Hands a shortcut to the scene's shell, keeping it until there is one: iOS
/// may run an intent before or after it connects the scene on a cold launch.
@MainActor
enum ShortcutInbox {
    private static var waiting: Shortcut?

    static var receiver: ((Shortcut) -> Void)? {
        didSet {
            if let receiver, let shortcut = take() { receiver(shortcut) }
        }
    }

    static func deliver(_ shortcut: Shortcut) {
        if let receiver { receiver(shortcut) } else { waiting = shortcut }
    }

    /// What arrived before the scene, for it to start on.
    static func take() -> Shortcut? {
        defer { waiting = nil }
        return waiting
    }
}

// MARK: - App Shortcuts

nonisolated struct NewChatIntent: AppIntent {
    static let title: LocalizedStringResource = "New chat"
    static let description = IntentDescription("Opens a new chat, ready to type or dictate.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.deliver(.newChat)
        return .result()
    }
}

nonisolated struct NewBotIntent: AppIntent {
    static let title: LocalizedStringResource = "New bot"
    static let description = IntentDescription("Opens New bot, to say what it should do.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.deliver(.newBot)
        return .result()
    }
}

nonisolated struct DecisionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Decisions"
    static let description = IntentDescription("Opens Decisions, what waits for you.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutInbox.deliver(.decisions)
        return .result()
    }
}

nonisolated struct ChatWithWorkShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .grayBlue }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewChatIntent(),
            phrases: [
                "New chat in \(.applicationName)",
                "Start a new chat in \(.applicationName)",
                "Start a chat in \(.applicationName)"
            ],
            shortTitle: "New chat",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: NewBotIntent(),
            phrases: [
                "New bot in \(.applicationName)",
                "Make a new bot in \(.applicationName)",
                "Make a bot in \(.applicationName)"
            ],
            shortTitle: "New bot",
            // App Shortcuts draw system symbols only, so a bot is its cpu
            // here, as where the apps can't draw the bot mark.
            systemImageName: "cpu"
        )
        AppShortcut(
            intent: DecisionsIntent(),
            phrases: [
                "Decisions in \(.applicationName)",
                "Open Decisions in \(.applicationName)",
                "Show my decisions in \(.applicationName)"
            ],
            shortTitle: "Decisions",
            systemImageName: "checklist"
        )
    }
}
