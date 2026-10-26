import Foundation
@preconcurrency import HotwireNative
import Observation
import WebKit

/// Loads the sidebar's JSON for one organization with the web views' own
/// session (their cookies and the app's user agent: no token of its own),
/// and keeps it while the shell lives.
///
/// It refetches when the sidebar opens, when a page says the list changed
/// (the `sidebar` bridge component), when the app comes back to the
/// foreground, and while a chat in it is working and the sidebar is open.
@MainActor
@Observable
final class SidebarStore {
    nonisolated enum Failure: Error, Equatable, Sendable {
        /// The server stopped recognizing the session.
        case signedOut
        /// Anything else: offline, a server that doesn't know the sidebar yet.
        case unavailable
    }

    private(set) var data: SidebarData?
    private(set) var failure: Failure?
    /// Every chat in the list, loaded the first time someone searches.
    private(set) var everyChat: [SidebarData.Chat]?
    private(set) var isLoading = false

    var account: AccountSlug?
    /// The list chosen in this organization, remembered between launches.
    var listKey: String? {
        get { account.flatMap { memory.listKey(in: $0) } }
        set { if let account { memory.setListKey(newValue, in: account) } }
    }

    /// Called when a fetch finds the session gone.
    var onSignedOut: (() -> Void)?

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let memory: SessionMemory
    @ObservationIgnored private var stale = true
    @ObservationIgnored private var generation = 0

    init(environment: AppEnvironment, account: AccountSlug?, memory: SessionMemory = .standard) {
        self.environment = environment
        self.account = account
        self.memory = memory
    }

    /// The page an organization's new chat opens on, the last time the JSON said.
    var newChatPath: String? { data?.links.newChat }

    // MARK: Loading

    func markStale() {
        stale = true
        everyChat = nil
    }

    func refreshIfStale() async {
        if stale || data == nil { await refresh() }
    }

    func refresh() async {
        guard let url = sidebarURL(all: false) else { return }
        generation += 1
        let mine = generation
        isLoading = true
        defer { if mine == generation { isLoading = false } }

        switch await Self.fetch(url, environment: environment) {
        case .success(let fresh):
            guard mine == generation else { return }
            data = fresh
            failure = nil
            stale = false
            if let newChat = fresh.links.newChat, let account { memory.setNewChatPath(newChat, in: account) }
        case .failure(let failure):
            guard mine == generation else { return }
            self.failure = failure
            if failure == .signedOut { onSignedOut?() }
        }
    }

    /// The next page of the list, appended.
    func loadMore() async {
        guard let next = data?.next, let current = data, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if case .success(let page) = await Self.fetch(environment.url(path: next), environment: environment), page.list.key == current.list.key {
            data = current.appending(page)
        }
    }

    /// Loads every chat in the list once, for a search.
    func loadEveryChat() async {
        guard everyChat == nil, let url = sidebarURL(all: true) else { return }
        if case .success(let all) = await Self.fetch(url, environment: environment) {
            everyChat = all.chats
        }
    }

    /// Shows a section opened or closed at once, before the server hears of
    /// it; the refetch its change causes keeps it so.
    func setCollapsed(_ collapsed: Bool, section id: Int) {
        guard let index = data?.sections?.firstIndex(where: { $0.id == id }) else { return }
        data?.sections?[index].collapsed = collapsed
    }

    func choose(list key: String) async {
        listKey = key
        everyChat = nil
        data = nil
        await refresh()
    }

    private func sidebarURL(all: Bool) -> URL? {
        guard let account else { return nil }
        var components = URLComponents(url: environment.url(path: AppPath.path("/native/sidebar", in: account)), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem]()
        if let listKey { items.append(URLQueryItem(name: "list", value: listKey)) }
        if all { items.append(URLQueryItem(name: "all", value: "1")) }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }

    // MARK: Fetching with the web views' session

    nonisolated static func fetch(_ url: URL, environment: AppEnvironment) async -> Result<SidebarData, Failure> {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        await WebSession.authorize(&request)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (body, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else {
            return .failure(.unavailable)
        }
        if http.statusCode == 401 { return .failure(.signedOut) }
        // A server that redirects signed-out requests to the sign-in page.
        if http.url.map({ AppRoute(url: $0).isSignIn }) == true { return .failure(.signedOut) }
        guard http.statusCode == 200, let data = try? SidebarData.decode(body) else { return .failure(.unavailable) }
        return .success(data)
    }
}

nonisolated extension SidebarData {
    /// This page with the next one's chats after its own.
    func appending(_ page: SidebarData) -> SidebarData {
        SidebarData(
            organization: organization, organizations: organizations, person: person, list: list, lists: lists,
            links: links, waiting: waiting, bots: bots, pins: pins, sections: sections, chats: chats + page.chats.filter { new in !chats.contains { $0.number == new.number } },
            next: page.next
        )
    }
}
