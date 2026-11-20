import BridgeComponents
import HotwireNative

/// Every bridge component the app registers. Their names appear in the user
/// agent (`bridge-components: [...]`), which is how the web knows which
/// Stimulus bridge controllers will find a native half.
///
/// The names and messages match Joe Masilotti's bridge-components wherever a
/// component exists there, so the web side can use his Stimulus controllers
/// and the Android app his Kotlin components. The contract for each is in
/// docs/server-contract.md.
enum BridgeRegistry {
    /// Whether the app draws the chat's composer itself (`composer`,
    /// ComposerController). Off for now (Carmine, 2026-11-20): the pages show
    /// the web composer, which the server leaves in sight when the user
    /// agent doesn't name `composer`. Turning it back on is this line.
    nonisolated static let drawsComposer = false

    static var all: [BridgeComponent.Type] {
        allComponents.filter { drawsComposer || $0 != ComposerComponent.self }
    }

    private static var allComponents: [BridgeComponent.Type] {
        [
            // Joe Masilotti's components, as they are.
            AlertComponent.self, // "alert"
            ReviewPromptComponent.self, // "review-prompt"
            ThemeComponent.self, // "theme"

            // Same names and messages as Joe's, rebuilt so that several can
            // share the navigation bar and look the part on iOS.
            NavigationButtonComponent.self, // "button"
            NavigationMenuComponent.self, // "menu"
            NavigationSearchComponent.self, // "search"
            FormSubmitComponent.self, // "form"
            ShareSheetComponent.self, // "share"
            NativeToastComponent.self, // "toast"
            HapticFeedbackComponent.self, // "haptic"

            // Chat with Work's own.
            ContextMenuComponent.self, // "context-menu"
            AuthSessionComponent.self, // "auth-session"
            NotificationTokenComponent.self, // "notification-token"
            SidebarComponent.self, // "sidebar"
            ComposerComponent.self, // "composer"
            FileShareComponent.self // "file"
        ]
    }
}
