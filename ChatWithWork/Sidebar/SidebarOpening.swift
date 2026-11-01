import Foundation

/// The page the sidebar is opening. The next screen takes it, so only that
/// screen gets the sidebar button: the same page reached later by a link, a
/// notification or from another page gets back, as any pushed page does.
final class SidebarOpening {
    private var location: URL?

    func opening(_ location: URL) {
        self.location = location
    }

    func take(_ location: URL?) -> Bool {
        defer { self.location = nil }
        return location != nil && location == self.location
    }
}
