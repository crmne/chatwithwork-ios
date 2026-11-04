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
                "organizations": "/accounts", "new_organization": "/accounts/new", "instructions": "/482139075/projects/3/instructions"},
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

    /// A server from 2026-11-01: bots with their lists, and each list's page.
    static let listsJSON = """
    {
      "organization": {"id": "482139075", "name": "Northwind Studio", "initials": "NS"},
      "organizations": [],
      "person": {"name": "Maya Hart", "initials": "MH"},
      "list": {"key": "recent", "name": "My chats", "kind": "recent", "hq": false, "url": null},
      "lists": [{"key": "recent", "name": "My chats", "kind": "recent", "hq": false, "pinned": false, "current": true, "url": null}],
      "links": {"chats": "/482139075/chats?list=recent"},
      "waiting": {"count": 0, "items": []},
      "bots": {"count": 1, "attention": true, "next_run": null, "url": "/482139075/bots", "new_url": "/482139075/bots/new",
        "list": {"key": "all", "name": "All bots", "kind": "all", "hq": false, "url": null},
        "lists": [
          {"key": "recent", "name": "My bots", "kind": "recent", "hq": false, "pinned": false, "current": false, "url": null, "new_url": "/482139075/bots/new"},
          {"key": "all", "name": "All bots", "kind": "all", "hq": false, "pinned": false, "current": true, "url": null, "new_url": "/482139075/bots/new"},
          {"key": "3", "name": "Support", "kind": "project", "hq": false, "pinned": false, "current": false, "url": "/482139075/projects/3", "new_url": "/482139075/bots/new?project_id=3"}
        ],
        "items": [
          {"id": 5, "name": "Front desk", "description": "Answers refunds", "lists": ["all", "3"], "url": "/482139075/bots/5", "group": "needs_you", "project": "Support", "state": "waiting", "state_label": "Waiting for you", "tone": "attention", "waiting": 1, "working": false, "next_run": null},
          {"id": 6, "name": "Morning plan", "description": null, "lists": ["all", "recent"], "url": "/482139075/bots/6", "group": "quiet", "project": null, "state": "idle", "state_label": "Idle", "tone": null, "waiting": 0, "working": false, "next_run": null}
        ]},
      "pins": [],
      "chats": [],
      "next": null
    }
    """

    @Test("a bot's lists narrow it, and a list no longer offered falls back to the server's")
    func botLists() throws {
        let bots = try #require(try SidebarData.decode(Data(Self.listsJSON.utf8)).bots)

        #expect(bots.chosenList("3")?.name == "Support")
        #expect(bots.chosenList("3")?.newUrl == "/482139075/bots/new?project_id=3")
        #expect(bots.chosenList("3")?.url == "/482139075/projects/3")
        #expect(bots.chosenList("99")?.key == "all")
        #expect(bots.chosenList(nil)?.key == "all")
        #expect(bots.items(in: "recent").map(\.name) == ["Morning plan"])
        #expect(bots.items(in: "3").map(\.name) == ["Front desk"])
        #expect(bots.items(in: "all").count == 2)
    }

    @Test("a bot's mark and line come as the web's row draws them, and an older server's bot has neither")
    func botMarks() throws {
        let json = """
        {"count": 1, "attention": true, "next_run": null, "items": [
          {"id": 5, "name": "Front desk", "url": "/1/bots/5", "group": "needs_you", "project": null, "state": "waiting", "state_label": "Waiting for you", "tone": "attention", "waiting": 1, "working": false, "next_run": null,
           "line": "Refund for order 1182 waits for you", "line_tone": "attention", "line_when": "9 min", "colour": "#F7C8B2", "face": "waiting"},
          {"id": 6, "name": "Morning plan", "url": "/1/bots/6", "group": "quiet", "project": null, "state": "idle", "state_label": "Idle", "tone": null, "waiting": 0, "working": false, "next_run": null,
           "line": "No runs yet", "line_tone": null, "line_when": null, "colour": "#FFFFFF", "face": null},
          {"id": 7, "name": "Old", "url": "/1/bots/7", "group": "quiet", "project": null, "state": "idle", "state_label": "Idle", "tone": null, "waiting": 0, "working": false, "next_run": null, "face": "winking"}]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try #require(try decoder.decode(SidebarData.Bots.self, from: Data(json.utf8)).items)

        #expect(items[0].line == "Refund for order 1182 waits for you")
        #expect(items[0].lineTone == "attention")
        #expect(items[0].lineWhen == "9 min")
        #expect(items[0].colour == "#F7C8B2")
        #expect(items[0].markFace == .waiting)
        #expect(items[1].markFace == nil && items[1].lineWhen == nil, "No face blinks")
        #expect(items[2].line == nil && items[2].colour == nil, "An older server's bot keeps the one-line row")
        #expect(items[2].markFace == nil, "A face this build doesn't know blinks")
    }

    @Test("the mark knows every face the server sends, with the web's eyes", arguments: ["thinking", "writing", "waiting", "happy", "flat"])
    func botFaces(face: String) throws {
        let known = try #require(BotMarkShape.Face(rawValue: face))
        #expect(!known.frames.isEmpty)
        #expect((known.step != nil) == (known.frames.count == 2), "Only the two-frame faces move")
    }

    @Test("a sticker's paper is the whole bubble, and its ink only the lines and eyes")
    func botSticker() {
        let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
        let paper = BotMarkShape(layer: .paper).path(in: rect)
        let ink = BotMarkShape().path(in: rect)
        #expect(paper.contains(CGPoint(x: 8.5, y: 9.5)), "The inside is paper")
        #expect(!ink.contains(CGPoint(x: 8.5, y: 9.5)), "The inside has no ink")
        #expect(ink.contains(CGPoint(x: 4.5, y: 5.5)) && paper.contains(CGPoint(x: 4.5, y: 5.5)), "An eye is ink over paper")
        #expect(!paper.contains(CGPoint(x: 0.5, y: 0.5)), "Outside the bubble is nothing")
    }

    @Test("keeps each organization's last sidebar for a launch offline, out of backups, until signing out")
    func cache() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "sidebar-cache-\(UUID().uuidString)")
        defer { SidebarCache.clear(in: folder) }
        let account = try #require(AccountSlug("482139075"))
        let other = try #require(AccountSlug("731000042"))

        #expect(SidebarCache.load(account, in: folder) == nil)
        SidebarCache.save(Data(Self.listsJSON.utf8), for: account, in: folder)
        #expect(SidebarCache.load(account, in: folder)?.organization.name == "Northwind Studio")
        #expect(SidebarCache.load(other, in: folder) == nil, "Each organization keeps its own")
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        SidebarCache.clear(in: folder)
        #expect(SidebarCache.load(account, in: folder) == nil)
    }

    @Test("the bots' search looks in every word of the name and what it does, ignoring case")
    func botSearch() throws {
        let bots = try #require(try SidebarData.decode(Data(Self.listsJSON.utf8)).bots?.items)
        let found = { (query: String) in bots.filter { $0.matches(query.lowercased().split(separator: " ")) }.map(\.name) }

        #expect(found("REFUNDS") == ["Front desk"])
        #expect(found("desk answers") == ["Front desk"])
        #expect(found("plan") == ["Morning plan"])
        #expect(found("waiting") == [], "Never its state")
    }

    @Test("a server from before the bots' lists decodes, and nothing is narrowed")
    func olderServerBots() throws {
        let json = """
        {"count": 0, "attention": false, "next_run": null, "url": "/1/bots", "new_url": "/1/bots/new", "items": [
          {"id": 5, "name": "Front desk", "url": "/1/bots/5", "group": "quiet", "project": null, "state": "idle", "state_label": "Idle", "tone": null, "waiting": 0, "working": false, "next_run": null}]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bots = try decoder.decode(SidebarData.Bots.self, from: Data(json.utf8))

        #expect(bots.lists == nil && bots.list == nil)
        #expect(bots.chosenList("all") == nil)
        #expect(bots.items(in: nil).count == 1)
        #expect(bots.items?.first?.matches(["front"]) == true)
    }

    @Test("reads the server's JSON")
    func decodes() throws {
        let data = try SidebarData.decode(Data(Self.json.utf8))
        #expect(data.organization.id == "482139075")
        #expect(data.organizations.count == 2)
        #expect(data.person.avatarUrl == nil)
        #expect(data.list.isProject)
        #expect(data.links.newChat == "/482139075/chats/new?project_id=3")
        #expect(data.links.instructions == "/482139075/projects/3/instructions")
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

    @Test("reads the person's sections, which older servers leave out")
    func sections() throws {
        let sectionsJSON = #""sections": [{"id": 7, "name": "Customers", "collapsed": false, "edit_url": "/482139075/sidebar/sections/7/edit", "collapse_url": "/482139075/sidebar/sections/7/collapse", "position_url": "/482139075/sidebar/sections/7/position", "chats": [{"number": 37, "title": "Initech renewal", "url": "/482139075/chats/37", "state": "processing", "waiting": false, "project": null, "asked_at": "2026-10-25T09:00:00Z", "group": "Today"}]}, {"id": 9, "name": "Hiring", "collapsed": true, "edit_url": "/482139075/sidebar/sections/9/edit", "collapse_url": "/482139075/sidebar/sections/9/collapse", "position_url": "/482139075/sidebar/sections/9/position", "chats": []}], "next": "#
        let json = Self.json.replacingOccurrences(of: #""next": "#, with: sectionsJSON)
        let data = try SidebarData.decode(Data(json.utf8))
        let sections = try #require(data.sections)
        #expect(sections.map(\.name) == ["Customers", "Hiring"])
        #expect(!sections[0].collapsed && sections[1].collapsed)
        #expect(sections[0].chats.map(\.number) == [37])
        #expect(sections[0].editUrl == "/482139075/sidebar/sections/7/edit")
        #expect(sections[0].rowID != sections[0].chats[0].sectionRowID)

        // An open section closes with a POST, a closed one opens with a DELETE.
        #expect(sections[0].toggleAction?.method == "post")
        #expect(sections[1].toggleAction?.method == "delete")
        #expect(sections[1].toggleAction?.url == "/482139075/sidebar/sections/9/collapse")
        #expect(sections[1].toggleAction?.opensPage == false)

        // A chat answering in a section counts as one the sidebar shows.
        #expect(data.everyChatShown.map(\.number) == [40, 37, 42, 41, 39])
        #expect(data.appending(data).sections == data.sections)

        let old = try SidebarData.decode(Data(Self.json.utf8))
        #expect(old.sections == nil)
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

    static let botsJSON = #""bots": {"count": 1, "attention": true, "next_run": null, "url": "/482139075/bots", "new_url": "/482139075/bots/new", "items": [{"id": 5, "name": "Front desk", "url": "/482139075/bots/5", "group": "needs_you", "project": "Launch", "state": "waiting", "state_label": "Waiting for you", "tone": "attention", "waiting": 1, "working": false, "next_run": null}, {"id": 3, "name": "Morning plan", "url": "/482139075/bots/3", "group": "quiet", "project": null, "state": "next", "state_label": "Next 08:30", "tone": "positive", "waiting": 0, "working": false, "next_run": "08:30"}, {"id": 2, "name": "Inbox triage", "url": "/482139075/bots/2", "group": "quiet", "project": null, "state": "paused", "state_label": "Paused", "tone": null, "waiting": 0, "working": true, "next_run": null}]}"#

    static func withBots(_ bots: String) -> String {
        json.replacingOccurrences(of: #""bots": {"count": 0, "attention": false, "next_run": "08:30"}"#, with: bots)
    }

    @Test("reads the person's bots for the Chats | Bots switch, which older servers leave out")
    func bots() throws {
        let data = try SidebarData.decode(Data(Self.withBots(Self.botsJSON).utf8))
        let bots = try #require(data.bots)
        #expect(bots.url == "/482139075/bots" && bots.newUrl == "/482139075/bots/new")
        let items = try #require(bots.items)
        #expect(items.map(\.name) == ["Front desk", "Morning plan", "Inbox triage"])
        #expect(items[0].needsYou && items[0].waiting == 1 && items[0].project == "Launch")
        #expect(items[1].stateLabel == "Next 08:30" && items[1].tone == "positive" && items[1].nextRun == "08:30")
        #expect(items[2].tone == nil && items[2].working)

        // Both headings only when both groups have bots.
        #expect(bots.groups.map(\.label) == ["Needs you", "Quiet"])
        #expect(bots.groups.map { $0.items.map(\.id) } == [[5], [3, 2]])
        // A working bot keeps the sidebar checking, like an answering chat.
        #expect(data.isAnythingWorking)

        let old = try SidebarData.decode(Data(Self.json.utf8))
        #expect(old.bots?.items == nil && old.bots?.url == nil)
    }

    @Test("lists bots under one heading-less list when only one group has any, and none when there are none")
    func botGroups() throws {
        let quietOnly = Self.botsJSON.replacingOccurrences(of: #""group": "needs_you""#, with: #""group": "quiet""#)
        let quiet = try #require(try SidebarData.decode(Data(Self.withBots(quietOnly).utf8)).bots)
        #expect(quiet.groups.count == 1 && quiet.groups[0].label == nil && quiet.groups[0].items.count == 3)

        let none = #""bots": {"count": 0, "attention": false, "next_run": null, "url": "/482139075/bots", "new_url": "/482139075/bots/new", "items": []}"#
        let empty = try #require(try SidebarData.decode(Data(Self.withBots(none).utf8)).bots)
        #expect(empty.items == [] && empty.groups.isEmpty)
    }

    @Test("reads who asks for each decision, which older servers leave out")
    func asker() throws {
        let json = Self.json.replacingOccurrences(of: #""kind": "approval", "project": "Website relaunch"}"#,
                                                  with: #""kind": "approval", "project": "Website relaunch", "summary": "Post the launch date", "asker": {"kind": "bot", "name": "Front desk", "project": "Launch"}}"#)
        let item = try #require(try SidebarData.decode(Data(json.utf8)).waiting.items.first)
        #expect(item.asker == SidebarData.Waiting.Asker(kind: "bot", name: "Front desk", project: "Launch"))
        #expect(item.summary == "Post the launch date")
        #expect(try SidebarData.decode(Data(Self.json.utf8)).waiting.items.first?.asker == nil)
    }

    @Test("remembers the chosen half on this install, and offers Bots only once the JSON lists them")
    @MainActor
    func half() {
        let memory = SessionMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let environment = AppEnvironment.load(info: ["CWWBaseURL": "https://chatwithwork.com"], arguments: UserDefaults(suiteName: UUID().uuidString)!, variables: [:])
        let store = SidebarStore(environment: environment, account: AccountSlug("482139075"), memory: memory)
        #expect(store.view == .chats)
        store.view = .bots
        #expect(memory.sidebarView == "bots")
        #expect(SidebarStore(environment: environment, account: AccountSlug("731000042"), memory: memory).view == .bots)
        // Nothing loaded yet: no switch, so the chats show.
        #expect(!store.offersBots && !store.showsBots)
    }

    @Test("Decisions' button tells VoiceOver how many wait, or that none do")
    func decisionsValue() {
        #expect(SidebarView.decisionsValue(0) == "None waiting")
        #expect(SidebarView.decisionsValue(1) == "1 waiting")
        #expect(SidebarView.decisionsValue(3) == "3 waiting")
    }

    @Test("adds a page's chats after the ones it has, once each")
    func appends() throws {
        let data = try SidebarData.decode(Data(Self.json.utf8))
        let more = data.appending(data)
        #expect(more.chats.count == data.chats.count)
    }

    @Test("remembers the list and new chat per organization, the sidebar's half, and the chat left last")
    func memory() {
        let memory = SessionMemory(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let acme = AccountSlug("482139075")!
        #expect(memory.listKey(in: acme) == nil)
        memory.setListKey("3", in: acme)
        #expect(memory.listKey(in: acme) == "3")
        memory.lastChat = ("/482139075/chats/42", Date())
        #expect(memory.lastChat?.path == "/482139075/chats/42")
        memory.sidebarView = "bots"
        #expect(memory.sidebarView == "bots")
        memory.reset()
        #expect(memory.listKey(in: acme) == nil)
        #expect(memory.sidebarView == nil)
        #expect(memory.lastChat == nil)
    }
}
