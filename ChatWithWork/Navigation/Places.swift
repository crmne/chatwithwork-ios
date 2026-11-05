import HotwireNative

/// Everything the sidebar opens is a place, never a step: it becomes the one
/// root screen, with the sidebar button and no back, so there's no history
/// of places to walk back through (docs/server-contract.md, section 5). The
/// path configuration names the places every link opens as the root
/// (`replace_root`: chats, Decisions, Bots, the lists, Settings); a page it
/// pushes elsewhere (a bot from Bots, a project from Projects) is a place
/// too when the sidebar opens it. Forms and pickers, its modals, still come
/// up over what's on screen.
nonisolated enum Places {
    /// The properties to route the sidebar's `properties` page with.
    static func opening(_ properties: PathProperties) -> PathProperties {
        guard properties.context != .modal else { return properties }
        var place = properties
        place["presentation"] = Navigation.Presentation.replaceRoot.rawValue
        return place
    }
}
