import Foundation
import Testing
@testable import ChatWithWork

/// The sidebar's JSON as the server sends it from /:account/native/sidebar
/// (docs/server-contract.md, "The sidebar").
@Suite("Sidebar")
struct SidebarTests {
    static let json = """
    {
      "organization": {"id": "482139075", "name": "Northwind Studio", "initials": "NS"},
      "organizations": [
        {"id": "482139075", "name": "Northwind Studio", "initials": "NS", "current": true, "role": "admin", "url": "/482139075/chats/new"},
        {"id": "731000042", "name": "Acme Robotics", "initials": "AR", "current": false, "role": "member", "url": "/731000042/chats/new"}
      ],
      "person": {"name": "Maya Hart", "email": "maya@northwind.example", "initials": "MH", "avatar_url": null},
      "list": {"key": "3", "name": "Website relaunch", "kind": "project", "hq": false},
      "lists": [
        {"key": "recent", "name": "Private chats", "kind": "recent", "hq": false, "pinned": false, "current": false},
        {"key": "all", "name": "All chats", "kind": "all", "hq": false, "pinned": false, "current": false},
        {"key": "3", "name": "Website relaunch", "kind": "project", "hq": false, "pinned": true, "current": true}
      ],
      "links": {"new_chat": "/482139075/chats/new?project_id=3", "bots": "/482139075/bots", "settings": "/482139075/settings",
                "projects": "/482139075/projects", "new_project": "/482139075/projects/new",
                "organizations": "/accounts", "new_organization": "/accounts/new"},
      "waiting": {"count": 1, "items": [{"title": "Launch date in #launch", "url": "/482139075/chats/42", "kind": "approval", "project": "Website relaunch"}]},
      "bots": {"count": 0, "attention": false, "next_run": "08:30"},
      "pins": [{"number": 40, "title": "Q3 launch plan", "url": "/482139075/chats/40", "state": "idle", "waiting": false, "project": null, "asked_at": "2026-10-20T08:12:00Z", "group": "Previous 7 days"}],
      "chats": [
        {"number": 42, "title": "Launch date in #launch", "url": "/482139075/chats/42", "state": "idle", "waiting": true, "project": "Website relaunch", "asked_at": "2026-10-25T08:12:00Z", "group": "Today"},
        {"number": 41, "title": "Lisbon offsite budget", "url": "/482139075/chats/41", "state": "processing", "waiting": false, "project": "Website relaunch", "asked_at": "2026-10-25T07:00:00Z", "group": "Today"},
        {"number": 39, "title": "Per-person column in euros", "url": "/482139075/chats/39", "state": "idle", "waiting": false, "project": "Website relaunch", "asked_at": "2026-10-24T09:00:00Z", "group": "Yesterday"}
      ],
      "next": "/482139075/native/sidebar?list=3&before=39&asked=2026-10-24T09:00:00.000000Z"
    }
    """

    @Test("reads the server's JSON")
    func decodes() throws {
        let data = try SidebarData.decode(Data(Self.json.utf8))
        #expect(data.organization.id == "482139075")
        #expect(data.organizations.count == 2)
        #expect(data.person.avatarUrl == nil)
        #expect(data.list.isProject)
        #expect(data.links.newChat == "/482139075/chats/new?project_id=3")
        #expect(data.waiting.items.first?.kind == "approval")
        #expect(data.bots?.nextRun == "08:30")
        #expect(data.chats[0].isWaiting && !data.chats[0].isWorking)
        #expect(data.chats[1].isWorking)
        #expect(data.next != nil)
    }

    @Test("reads a chat's long-press actions and the Decisions page, which older servers leave out")
    func actionsAndDecisions() throws {
        let json = Self.json
            .replacingOccurrences(of: #""waiting": {"count": 1, "items""#, with: #""waiting": {"count": 1, "url": "/482139075/decisions", "items""#)
            .replacingOccurrences(of: #""group": "Today"},"#, with: #""group": "Today", "actions": [{"key": "pin", "title": "Pin", "method": "post", "url": "/482139075/chats/42/pin", "iosImage": "pin", "androidImage": "keep"}, {"key": "delete", "title": "Delete", "method": "delete", "url": "/482139075/chats/42", "iosImage": "trash", "androidImage": "delete", "confirm": "Delete this chat?", "destructive": true}, {"key": "rename", "title": "Rename", "method": "get", "url": "/482139075/chats/42/edit", "iosImage": "pencil", "androidImage": "edit"}]},"#)
        let data = try SidebarData.decode(Data(json.utf8))
        #expect(data.waiting.url == "/482139075/decisions")
        let actions = try #require(data.chats[0].actions)
        #expect(actions.map(\.key) == ["pin", "delete", "rename"])
        #expect(actions[1].confirm == "Delete this chat?" && actions[1].destructive == true && !actions[1].opensPage)
        #expect(actions[2].opensPage && actions[2].iosImage == "pencil")

        let old = try SidebarData.decode(Data(Self.json.utf8))
        #expect(old.waiting.url == nil && old.chats[0].actions == nil)
    }

    @Test("reads a guest's, with what they can't reach left out")
    func guest() throws {
        let json = Self.json
            .replacingOccurrences(of: #""new_chat": "/482139075/chats/new?project_id=3""#, with: #""new_chat": null"#)
            .replacingOccurrences(of: #""bots": "/482139075/bots""#, with: #""bots": null"#)
            .replacingOccurrences(of: #""bots": {"count": 0, "attention": false, "next_run": "08:30"}"#, with: #""bots": null"#)
        let data = try SidebarData.decode(Data(json.utf8))
        #expect(data.links.newChat == nil)
        #expect(data.links.bots == nil)
        #expect(data.bots == nil)
    }

    @Test("keeps the server's groups in order")
    func groups() throws {
        let data = try SidebarData.decode(Data(Self.json.utf8))
        let groups = SidebarData.grouped(data.chats)
        #expect(groups.map(\.label) == ["Today", "Yesterday"])
        #expect(groups[0].chats.map(\.number) == [42, 41])
    }

    @Test("adds a page's chats after the ones it has, once each")
    func appends() throws {
        let data = try SidebarData.decode(Data(Self.json.utf8))
        let more = data.appending(data)
        #expect(more.chats.count == data.chats.count)
    }

    @Test("remembers the list and new chat per organization, and the chat left last")
    func memory() {
        let memory = SessionMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let acme = AccountSlug("482139075")!
        #expect(memory.listKey(in: acme) == nil)
        memory.setListKey("3", in: acme)
        #expect(memory.listKey(in: acme) == "3")
        memory.lastChat = ("/482139075/chats/42", Date())
        #expect(memory.lastChat?.path == "/482139075/chats/42")
        memory.reset()
        #expect(memory.listKey(in: acme) == nil)
        #expect(memory.lastChat == nil)
    }
}
