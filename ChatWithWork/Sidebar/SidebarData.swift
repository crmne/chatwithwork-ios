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

        var id: Int { number }
        var isWorking: Bool { state == "processing" }
        var isWaiting: Bool { waiting == true }
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
    let chats: [Chat]
    let next: String?

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
