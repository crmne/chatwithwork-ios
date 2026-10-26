import Foundation

/// What the sidebar shows, as the server sends it from
/// `GET /:account/native/sidebar` (docs/server-contract.md, "The sidebar").
/// Every URL in it is a path on this server.
nonisolated struct SidebarData: Decodable, Equatable, Sendable {
    struct Organization: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        let initials: String
        let current: Bool?
        let role: String?
        let url: String?
    }

    struct Person: Decodable, Equatable, Sendable {
        let name: String
        let email: String?
        let initials: String
        let avatarUrl: String?
    }

    struct List: Decodable, Equatable, Sendable, Identifiable {
        let key: String
        let name: String
        let kind: String
        let hq: Bool?
        let pinned: Bool?
        let current: Bool?

        var id: String { key }
        var isProject: Bool { kind == "project" }
    }

    struct Links: Decodable, Equatable, Sendable {
        let newChat: String?
        let bots: String?
        let settings: String?
        let projects: String?
        let newProject: String?
        let organizations: String?
        let newOrganization: String?
        let decisions: String?
    }

    struct Waiting: Decodable, Equatable, Sendable {
        struct Item: Decodable, Equatable, Sendable, Identifiable {
            let title: String
            let url: String
            let kind: String
            let project: String?

            var id: String { url + kind }
        }

        let count: Int
        let items: [Item]
        /// The Decisions page (servers from 2026-10-26).
        let url: String?
    }

    struct Bots: Decodable, Equatable, Sendable {
        let count: Int
        let attention: Bool
        let nextRun: String?
    }

    struct Chat: Decodable, Equatable, Sendable, Identifiable {
        let number: Int
        let title: String
        let url: String
        let state: String
        let waiting: Bool?
        let project: String?
        let askedAt: String?
        let group: String?
        /// What a long press offers, as the web row's menu does.
        let actions: [Action]?

        var id: Int { number }
        /// Its row's id among the pins, apart from its row in the list.
        var pinID: String { "pin-\(number)" }
        /// Its row's id in a section (a chat sits in at most one of them).
        var sectionRowID: String { "section-chat-\(number)" }
        var isWorking: Bool { state == "processing" }
        var isWaiting: Bool { waiting == true }
    }

    /// One of the person's own sidebar sections (the server's `ChatSection`):
    /// a heading of theirs holding this list's chats they put in it, newest
    /// question first, opened or closed as they left it on any device.
    struct Section: Decodable, Equatable, Sendable, Identifiable {
        let id: Int
        let name: String
        var collapsed: Bool
        let chats: [Chat]
        /// Its Rename page.
        let editUrl: String?
        /// POST closes it, DELETE opens it.
        let collapseUrl: String?
        /// PATCH with `position` moves it.
        let positionUrl: String?

        /// Its header's id in the list, apart from any chat's.
        var rowID: String { "section-\(id)" }

        /// Opening or closing it on the server, sent like a chat's action
        /// by the page on screen, or nil from a server without the URL.
        var toggleAction: Action? {
            collapseUrl.map { url in
                Action(key: "collapse", title: name, method: collapsed ? "delete" : "post", url: url, iosImage: nil, confirm: nil, destructive: nil)
            }
        }
    }

    /// One of a chat's actions: `get` opens `url`, any other method goes to
    /// the page on screen to send (SidebarComponent), behind `confirm`.
    struct Action: Decodable, Equatable, Sendable, Identifiable {
        let key: String
        let title: String
        let method: String
        let url: String
        let iosImage: String?
        let confirm: String?
        let destructive: Bool?

        var id: String { key }
        var opensPage: Bool { method == "get" }
    }

    let organization: Organization
    let organizations: [Organization]
    let person: Person
    let list: List
    let lists: [List]
    let links: Links
    let waiting: Waiting
    let bots: Bots?
    let pins: [Chat]
    /// The person's sections, in their order (servers from 2026-10-26);
    /// `chats` are then the list's chats in none of them.
    var sections: [Section]?
    let chats: [Chat]
    let next: String?

    /// Every chat it names: pins, the sections' chats and the list's.
    var everyChatShown: [Chat] { pins + (sections ?? []).flatMap(\.chats) + chats }

    static func decode(_ data: Data) throws -> SidebarData {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SidebarData.self, from: data)
    }

    /// The chats in their groups ("Today", "Yesterday"...), in order.
    static func grouped(_ chats: [Chat]) -> [(label: String, chats: [Chat])] {
        var groups: [(label: String, chats: [Chat])] = []
        for chat in chats {
            let label = chat.group ?? ""
            if let last = groups.indices.last, groups[last].label == label {
                groups[last].chats.append(chat)
            } else {
                groups.append((label, [chat]))
            }
        }
        return groups
    }
}
