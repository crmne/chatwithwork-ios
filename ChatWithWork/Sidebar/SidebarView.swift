import SwiftUI
import UIKit

/// What the sidebar does when someone picks something in it. The shell
/// routes paths through its navigator and closes the sidebar.
struct SidebarActions {
    var open: (String) -> Void
    var newChat: () -> Void
    var chooseList: (String) -> Void
    /// A chat's action from its long-press menu.
    var perform: (SidebarData.Action) -> Void
    /// Opens or closes one of the person's sections.
    var toggleSection: (SidebarData.Section) -> Void
}

/// The sidebar: the same things in the same order, and the same measures, as
/// the web's at a phone's width (chats/_sidebar_chats, bots/_sidebar_list,
/// application/_me_menu), drawn natively from `/native/sidebar`. Decisions at
/// the top, then the Chats | Bots switch, the head (the list selector and a
/// square plus), and the search, which all stay put as the views switch. Under
/// them Chats lists the pins, the person's own sections, and the chats in none
/// of them by latest question, ending in the list's page; Bots lists the
/// chosen list's bots. The person sits at the foot. A long press on a chat
/// opens its menu, as the web row's does.
///
/// A server that sends no `bots.lists` gets a card opening the Bots page in
/// the Bots view's head; one that sends no `bots.items`, the Bots row instead
/// of the switch.
struct SidebarView: View {
    /// The switch's two halves.
    nonisolated enum Half: String, Sendable {
        case chats, bots
    }

    @Bindable var store: SidebarStore
    let actions: SidebarActions
    /// The path on screen, to mark its row.
    var currentPath: String?

    @State private var query = ""
    @State private var showsWaiting = false

    // The web's type sizes, following Dynamic Type from there.
    @ScaledMetric(relativeTo: .subheadline) private var rowSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var smallSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var microSize: CGFloat = 11

    private var words: [Substring] { query.lowercased().split(separator: " ") }

    var body: some View {
        VStack(spacing: 0) {
            if let data = store.data {
                VStack(spacing: 8) {
                    // Decisions first, just before the switch (or at the top
                    // where there's none), as the web's decisions/_sidebar_button.
                    if let decisions = data.waiting.url ?? data.links.decisions {
                        decisionsButton(count: data.waiting.count, path: decisions)
                    }
                    if store.offersBots, let bots = data.bots {
                        halfSwitch(attention: bots.attention)
                    }
                    head(data)
                    searchField(data)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if store.showsBots, let bots = data.bots {
                            botsList(bots)
                        } else {
                            places(data)
                            if query.isEmpty {
                                pinnedChats(data)
                                chatsList(data)
                            } else {
                                searchResults(data)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.immediately)

                personFooter(data)
            } else {
                placeholder
            }
        }
        .background(Color(Palette.canvasSunken).ignoresSafeArea())
        .tint(Color(Palette.ink))
    }

    // MARK: Head

    /// The same row in both views: what the view is about, and the same
    /// square plus beside it. A guest gets no plus, and the selector the row.
    @ViewBuilder
    private func head(_ data: SidebarData) -> some View {
        HStack(spacing: 6) {
            if store.showsBots, let bots = data.bots {
                if let lists = bots.lists, let list = store.botList {
                    listSelector(list, choices: lists, data: data, waiting: bots.items(in: list.key).reduce(0) { $0 + $1.waiting }) {
                        store.botListKey = $0.key
                    }
                } else {
                    botsCard(data, bots)
                }
                if let newBot = store.botList?.newUrl ?? bots.newUrl {
                    newButton(name: "New bot", identifier: "sidebar.newBot", isCurrent: isCurrent(newBot)) { actions.open(newBot) }
                }
            } else {
                listSelector(data.list, choices: data.lists, data: data, waiting: 0) { actions.chooseList($0.key) }
                if let newChat = data.links.newChat {
                    newButton(name: "New chat", identifier: "sidebar.newChat", isCurrent: isCurrent(newChat), action: actions.newChat)
                }
            }
        }
    }

    /// New chat or New bot, one drawing: a square as tall as the selector
    /// with its hairline, raised while it's the page on screen.
    private func newButton(name: LocalizedStringKey, identifier: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(Palette.ink))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(isCurrent ? Color(Palette.surface) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(Palette.line), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// Whether a sidebar link leads to the page on screen, its query aside.
    private func isCurrent(_ path: String) -> Bool {
        currentPath.map { AppRoute(path: $0).path == AppRoute(path: path).path } ?? false
    }

    /// The web's list switcher, for chats or bots: My and All, the projects
    /// the person is on, then the chosen project's page, All projects… and
    /// New project. `waiting` is what the Bots view says after the list's name.
    private func listSelector(_ list: SidebarData.List, choices: [SidebarData.List], data: SidebarData, waiting: Int, choose: @escaping (SidebarData.List) -> Void) -> some View {
        Menu {
            Section {
                ForEach(choices.filter { !$0.isProject }) { choice in
                    listChoice(choice, chosen: choice.key == list.key, choose: choose)
                }
            }
            let projects = choices.filter(\.isProject)
            if !projects.isEmpty {
                Section("Projects you're on") {
                    ForEach(projects) { choice in
                        listChoice(choice, chosen: choice.key == list.key, choose: choose)
                    }
                }
            }
            Section {
                if let page = list.url {
                    Button { actions.open(page) } label: { Label("Open \(list.name)", systemImage: "arrow.up.right.square") }
                }
                if let projects = data.links.projects {
                    Button { actions.open(projects) } label: { Label("All projects…", systemImage: "square.grid.2x2") }
                }
                if let newProject = data.links.newProject {
                    Button { actions.open(newProject) } label: { Label("New project", systemImage: "plus") }
                }
            }
        } label: {
            HStack(spacing: 8) {
                listIcon(list)
                    .foregroundStyle(Color(Palette.inkMuted))
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(Palette.canvasSunken)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(Palette.line), lineWidth: 1))
                Text(list.name)
                    .font(.system(size: rowSize, weight: .semibold))
                    .foregroundStyle(Color(Palette.ink))
                    .lineLimit(1)
                if waiting > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(Color(Palette.attention)).frame(width: 6, height: 6)
                        Text("\(waiting) waiting")
                            .font(.system(size: captionSize))
                            .foregroundStyle(Color(Palette.attentionInk))
                    }
                    .fixedSize()
                    .accessibilityLabel("\(waiting) waiting for you")
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(Palette.inkFaint))
                    .padding(.trailing, 2)
            }
            .padding(.horizontal, 4)
            .padding(.leading, 4)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(Palette.surface)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(Palette.line), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("sidebar.list")
        .accessibilityLabel("Showing \(list.name)")
    }

    /// One choice in the selector: a check on the chosen one, a pin on a
    /// pinned project, and what the web's menu notes under the name.
    private func listChoice(_ choice: SidebarData.List, chosen: Bool, choose: @escaping (SidebarData.List) -> Void) -> some View {
        Button { choose(choice) } label: {
            Text(choice.name)
            if choice.kind == "recent" {
                Text("only you")
            } else if choice.hq == true {
                Text("HQ")
            }
            if chosen {
                Image(systemName: "checkmark")
            } else if choice.isProject {
                Image(systemName: choice.pinned == true ? "pin" : "folder")
            }
        }
    }

    /// The web's `chat_list_icon`.
    @ViewBuilder
    private func listIcon(_ list: SidebarData.List) -> some View {
        if list.isProject {
            Image(systemName: "folder").font(.system(size: 14, weight: .semibold))
        } else if list.kind == "recent" {
            Image(systemName: "lock").font(.system(size: 14, weight: .semibold))
        } else if store.showsBots {
            BotMark(size: 16, face: nil)
        } else {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 12, weight: .semibold))
        }
    }

    /// Under the head, in both views, its hint naming what it searches. The
    /// first search of the chats loads every chat left.
    private func searchField(_ data: SidebarData) -> some View {
        let list = store.showsBots ? store.botList : data.list
        let hint = list.flatMap { $0.isProject ? $0.name : nil } ?? (store.showsBots ? String(localized: "bots") : String(localized: "chats"))
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(Palette.inkFaint))
            TextField(String(localized: "Search \(hint)"), text: $query)
                .font(.system(size: smallSize))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("sidebar.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color(Palette.inkFaint))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(Palette.surface)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(Palette.line), lineWidth: 1))
        .onChange(of: query) { _, value in
            if !value.isEmpty, !store.showsBots { Task { await store.loadEveryChat() } }
        }
    }

    // MARK: Places

    /// What older servers have in the list: what waits, and the Bots row.
    @ViewBuilder
    private func places(_ data: SidebarData) -> some View {
        // Decisions is a button at the sidebar's top once the server names
        // its page. A server without one keeps it here, a row listing what
        // waits.
        if data.waiting.url == nil && data.links.decisions == nil {
            decisionsRow(data)
        }

        if !store.offersBots, let bots = data.links.bots {
            placeRow("Bots", icon: BotMark(), identifier: "sidebar.bots", trailing: {
                if let meta = data.bots {
                    if meta.count > 0 || meta.attention {
                        HStack(spacing: 5) {
                            Circle().fill(Color(Palette.attention)).frame(width: 7, height: 7)
                            if meta.count > 0 {
                                Text("\(meta.count)").font(.caption.monospacedDigit()).foregroundStyle(Color(Palette.inkMuted))
                            }
                        }
                    } else if let next = meta.nextRun {
                        Text(next).font(.caption.monospaced()).foregroundStyle(Color(Palette.inkMuted))
                    }
                }
            }) {
                actions.open(bots)
            }
        }
    }

    /// Decisions, the one place what waits for the person gathers: a button
    /// of its own, outlined like the list switcher since it's the one thing
    /// here that asks for the person. The list-checks icon, "Decisions"
    /// spelled out, and at its end how many wait on the attention wash, or the
    /// happy bot and a quiet "All clear". While something waits its outline takes the attention
    /// edge, as the web's `.decisions-button` does.
    private func decisionsButton(count: Int, path: String) -> some View {
        let current = currentPath.map { AppRoute(path: $0).path.hasPrefix(AppRoute(path: path).path) } ?? false
        let waits = count > 0
        return Button { actions.open(path) } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: rowSize, weight: .semibold))
                    .foregroundStyle(Color(Palette.inkMuted))
                    .frame(width: 20)
                Text("Decisions")
                    .font(.system(size: rowSize, weight: .semibold))
                    .foregroundStyle(Color(Palette.ink))
                Spacer(minLength: 0)
                if waits {
                    Text("\(count)")
                        .font(.system(size: captionSize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(Palette.attentionInk))
                        .padding(.horizontal, 7)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Capsule().fill(Color(Palette.attention).opacity(0.16)))
                        .overlay(Capsule().stroke(Color(Palette.attention).opacity(0.45), lineWidth: 1))
                } else {
                    HStack(spacing: 4) {
                        BotMark(size: 16, face: .happy)
                        Text("All clear").font(.system(size: microSize, design: .monospaced))
                    }
                    .foregroundStyle(Color(Palette.inkFaint))
                    .padding(.trailing, 4)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(current ? Palette.surfaceRaised : Palette.surface)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(waits ? Color(Palette.attention).opacity(0.45) : Color(current ? Palette.lineStrong : Palette.line), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Decisions")
        .accessibilityValue(Self.decisionsValue(count))
        .accessibilityIdentifier("sidebar.decisions")
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    /// What VoiceOver says of Decisions' count.
    static func decisionsValue(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "None waiting")
        case 1: String(localized: "1 waiting")
        default: String(localized: "\(count) waiting")
        }
    }

    /// Decisions as older servers have them: a row that opens the list of
    /// what waits beneath it.
    @ViewBuilder
    private func decisionsRow(_ data: SidebarData) -> some View {
        placeRow("Decisions", systemImage: "hand.raised", identifier: "sidebar.waiting", trailing: {
            if data.waiting.count > 0 {
                HStack(spacing: 5) {
                    Circle().fill(Color(Palette.attention)).frame(width: 7, height: 7)
                    Text("\(data.waiting.count)").font(.caption.monospacedDigit()).foregroundStyle(Color(Palette.inkMuted))
                }
            }
        }) {
            withAnimation(.snappy) { showsWaiting.toggle() }
        }

        if showsWaiting {
            if data.waiting.items.isEmpty {
                Text("No decisions are waiting.")
                    .font(.footnote)
                    .foregroundStyle(Color(Palette.inkMuted))
                    .padding(.leading, 40)
                    .padding(.vertical, 6)
            } else {
                ForEach(data.waiting.items) { item in
                    Button { actions.open(item.url) } label: {
                        HStack(spacing: 8) {
                            Group {
                                if item.kind == "bot" {
                                    BotMark(size: 16)
                                } else {
                                    Image(systemName: waitingSymbol(item.kind)).font(.footnote)
                                }
                            }
                            .foregroundStyle(Color(Palette.attentionInk))
                            .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                // Who asks first, as the web's decision row leads with it.
                                Text(item.asker?.name ?? item.title).lineLimit(1).foregroundStyle(Color(Palette.ink))
                                Text(waitingLabel(item)).font(.caption).foregroundStyle(Color(Palette.inkMuted)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                        .padding(.leading, 30)
                        .padding(.trailing, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar.waiting.item")
                }
            }
        }
    }

    /// Chats | Bots, just under Decisions at the sidebar's top: two equal halves, each its icon and
    /// label centred together. The Bots half carries a dot, never a number,
    /// while a bot needs the person: Decisions holds the one count.
    private func halfSwitch(attention: Bool) -> some View {
        HStack(spacing: 2) {
            halfButton(.chats, title: "Chats", attention: false) {
                Image(systemName: "bubble.left.and.bubble.right").font(.footnote.weight(.semibold))
            }
            halfButton(.bots, title: "Bots", attention: attention) {
                // Down a point, so the bubble's middle meets the label's, as the chats icon's does.
                BotMark(size: 15).offset(y: 1)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(Palette.ink).opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(Palette.line), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }

    /// One half. Chosen or not, it has the same size, padding and type, so
    /// nothing moves when the switch changes; only its fill and ink do. The
    /// attention dot hangs just past the label, outside the centred group.
    private func halfButton(_ half: Half, title: LocalizedStringKey, attention: Bool, @ViewBuilder icon: () -> some View) -> some View {
        let chosen = store.view == half
        return Button {
            query = ""
            withAnimation(.snappy) { store.view = half }
        } label: {
            HStack(spacing: 7) {
                icon().frame(width: 16, height: 16).accessibilityHidden(true)
                Text(title)
                    .font(.system(size: smallSize, weight: .medium))
                    .overlay(alignment: .trailing) {
                        if attention {
                            Circle().fill(Color(Palette.attention))
                                .frame(width: 6, height: 6)
                                .offset(x: 10)
                        }
                    }
            }
            .foregroundStyle(Color(chosen ? Palette.ink : Palette.inkMuted))
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(chosen ? Color(Palette.surfaceRaised) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(chosen ? Color(Palette.line) : .clear, lineWidth: 1))
                    .shadow(color: .black.opacity(chosen ? 0.08 : 0), radius: 1, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.switch.\(half.rawValue)")
        .accessibilityValue(attention ? String(localized: "A bot needs you") : "")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    private func placeRow(_ title: LocalizedStringKey, systemImage: String, identifier: String, @ViewBuilder trailing: () -> some View = { EmptyView() }, action: @escaping () -> Void) -> some View {
        placeRow(title, icon: Image(systemName: systemImage).font(.body), identifier: identifier, trailing: trailing, action: action)
    }

    private func placeRow(_ title: LocalizedStringKey, icon: some View, identifier: String, @ViewBuilder trailing: () -> some View = { EmptyView() }, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 22)
                Text(title).font(.body.weight(.medium))
                Spacer(minLength: 0)
                trailing()
            }
            .foregroundStyle(Color(Palette.ink))
            .padding(.horizontal, 8)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Chats

    @ViewBuilder
    private func pinnedChats(_ data: SidebarData) -> some View {
        if !data.pins.isEmpty {
            sectionLabel("Pinned", top: 4)
            // A pinned chat is also in its day's list: the rows need ids of
            // their own, or the lazy stack leaves a gap where one should be.
            ForEach(data.pins, id: \.pinID) { chat in chatRow(chat, pinned: true) }
            Spacer(minLength: 8).frame(height: 8)
        }
    }

    @ViewBuilder
    private func chatsList(_ data: SidebarData) -> some View {
        let sections = data.sections ?? []
        ForEach(sections, id: \.rowID) { section in
            sectionHeader(section)
            if !section.collapsed {
                ForEach(section.chats, id: \.sectionRowID) { chat in chatRow(chat, pinned: false) }
            }
        }

        if data.chats.isEmpty {
            if sections.allSatisfy(\.chats.isEmpty) {
                muted(emptyList(data.list))
            }
        } else {
            // As the web's sidebar: below the sections, the rest under one heading.
            if !sections.isEmpty { sectionLabel("Other chats") }
            ForEach(data.chats) { chat in chatRow(chat, pinned: false) }
            if data.next != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onAppear { Task { await store.loadMore() } }
            } else if let page = data.links.chats {
                seeAll(data.list, page: page)
            }
        }
    }

    private func emptyList(_ list: SidebarData.List) -> String {
        if list.isProject { return String(localized: "No chats in \(list.name) yet.") }
        return list.kind == "all" ? String(localized: "Chats you can read show up here.") : String(localized: "Your chats show up here.")
    }

    /// A line where a list holds nothing.
    private func muted(_ text: String) -> some View {
        Text(text)
            .font(.system(size: smallSize))
            .foregroundStyle(Color(Palette.inkFaint))
            .padding(.horizontal, 10)
            .padding(.top, 12)
    }

    /// The end of a list that holds everything: its page, with every chat by
    /// date, or the project's, as the web's chats/_sidebar_see_all.
    private func seeAll(_ list: SidebarData.List, page: String) -> some View {
        Button { actions.open(page) } label: {
            HStack(spacing: 6) {
                Text(list.isProject ? String(localized: "Open \(list.name)") : String(localized: "See all, by date")).lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: captionSize, weight: .medium))
            }
            .font(.system(size: smallSize))
            .foregroundStyle(Color(Palette.inkFaint))
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 5)
        .accessibilityIdentifier("sidebar.seeAll")
    }

    /// A section's heading, as the web's: a caret, its name and how many
    /// chats it holds. A tap opens or closes it; a long press offers Rename.
    private func sectionHeader(_ section: SidebarData.Section) -> some View {
        Button { withAnimation(.snappy) { actions.toggleSection(section) } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(section.collapsed ? 0 : 90))
                    .frame(width: 12)
                Text(section.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(section.chats.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(Palette.inkFaint))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(Palette.inkMuted))
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .frame(minHeight: 36, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let edit = section.editUrl {
                Button { actions.open(edit) } label: { Label("Rename", systemImage: "pencil") }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.name)
        .accessibilityValue(section.collapsed ? String(localized: "Closed, \(section.chats.count) chats") : String(localized: "Open, \(section.chats.count) chats"))
        .accessibilityIdentifier("sidebar.section")
        .accessibilityAddTraits([.isHeader, .isButton])
    }

    // MARK: Bots

    /// In the list switcher's place: the bots in this organization, how many,
    /// and what's working or waiting, opening the Bots page.
    private func botsCard(_ data: SidebarData, _ bots: SidebarData.Bots) -> some View {
        let items = bots.items ?? []
        let working = items.filter(\.working).count
        let waiting = items.reduce(0) { $0 + $1.waiting }
        return Button {
            if let url = bots.url ?? data.links.bots { actions.open(url) }
        } label: {
            HStack(spacing: 10) {
                BotMark(size: 18)
                    .foregroundStyle(Color(Palette.inkInverted))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.ink)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("BOTS IN \(data.organization.name.uppercased())")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color(Palette.inkMuted))
                        .lineLimit(1)
                    Text(botCount(items.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Palette.ink))
                        .lineLimit(1)
                    if working > 0 || waiting > 0 {
                        HStack(spacing: 8) {
                            if working > 0 { stateText(String(localized: "\(working) working"), tone: "live") }
                            if waiting > 0 { stateText(String(localized: "\(waiting) waiting for you"), tone: "attention") }
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color(Palette.inkMuted))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(Palette.surface)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(Palette.line), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.botsCard")
    }

    /// The chosen list's bots, narrowed by the search. A heading the search
    /// empties goes with its rows.
    @ViewBuilder
    private func botsList(_ bots: SidebarData.Bots) -> some View {
        let listed = bots.lists == nil ? (bots.items ?? []) : bots.items(in: store.botList?.key)
        let found = listed.filter { $0.matches(words) }
        if (bots.items ?? []).isEmpty {
            muted(String(localized: "Your bots, and the ones shared with you, show up here."))
            if let newBot = store.botList?.newUrl ?? bots.newUrl {
                Button { actions.open(newBot) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        Text("New bot").font(.system(size: smallSize, weight: .medium))
                    }
                    .foregroundStyle(Color(Palette.inkInverted))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(Palette.ink)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .accessibilityIdentifier("sidebar.firstBot")
            }
        } else if listed.isEmpty {
            muted(String(localized: "No bots here yet."))
        } else if found.isEmpty {
            muted(String(localized: "No bots match."))
        } else {
            let groups = SidebarData.Bots.groups(found)
            ForEach(groups, id: \.label) { group in
                if let label = group.label {
                    sectionLabel(label)
                } else {
                    Spacer(minLength: 8).frame(height: 8)
                }
                ForEach(group.items) { bot in botRow(bot) }
            }
        }
    }

    /// One bot: its mark (with a live dot while it works), its name, the
    /// project icon of a shared one, and its one state at the end, as the
    /// web's bots/_sidebar_bot: how many decisions wait in it, Failed,
    /// Paused, or when a time next starts it. Working shows on the mark alone.
    private func botRow(_ bot: SidebarData.Bots.Item) -> some View {
        let current = currentPath.map { path in
            let mine = AppRoute(path: bot.url).path
            let here = AppRoute(path: path).path
            return here == mine || here.hasPrefix(mine + "/")
        } ?? false
        return Button { actions.open(bot.url) } label: {
            HStack(spacing: 10) {
                BotMark(size: 18)
                    .foregroundStyle(Color(bot.state == "paused" ? Palette.inkFaint : Palette.inkMuted))
                    .overlay(alignment: .bottomTrailing) {
                        if bot.working {
                            Circle().fill(Color(Palette.live))
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color(Palette.canvasSunken), lineWidth: 1.5))
                                .offset(x: 2, y: 1)
                        }
                    }
                Text(bot.name)
                    .lineLimit(1)
                    .font(.system(size: rowSize))
                    .foregroundStyle(Color(current ? Palette.ink : bot.state == "paused" ? Palette.inkFaint : Palette.inkMuted))
                if bot.project != nil {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(Palette.inkFaint))
                }
                Spacer(minLength: 0)
                botState(bot)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 35)
            .background(rowBackground(current: current))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bot.project.map { String(localized: "\(bot.name), shared in \($0)") } ?? bot.name)
        .accessibilityValue(botValue(bot))
        .accessibilityIdentifier("sidebar.bot")
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func botState(_ bot: SidebarData.Bots.Item) -> some View {
        if bot.waiting > 0 {
            HStack(spacing: 5) {
                Circle().fill(Color(Palette.attention)).frame(width: 6, height: 6)
                Text("\(bot.waiting)").font(.system(size: microSize, design: .monospaced)).foregroundStyle(Color(Palette.inkFaint))
            }
            .fixedSize()
        } else if bot.state == "failed" {
            Text("Failed").font(.system(size: captionSize)).foregroundStyle(Color(Palette.negativeInk)).fixedSize()
        } else if bot.state == "paused" {
            Text("Paused").font(.system(size: captionSize)).foregroundStyle(Color(Palette.inkFaint)).fixedSize()
        } else if bot.state == "next", let next = bot.nextRun {
            Text(next).font(.system(size: microSize, design: .monospaced)).foregroundStyle(Color(Palette.inkFaint)).fixedSize()
        }
    }

    /// The page on screen's row: raised, as the web's `aria-current`.
    @ViewBuilder
    private func rowBackground(current: Bool) -> some View {
        if current {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(Palette.line), lineWidth: 1))
        }
    }

    /// A state in words with a dot in its tone, as the web's `.state`.
    private func stateText(_ label: String, tone: String?) -> some View {
        HStack(spacing: 5) {
            if let color = toneColor(tone) {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(label).font(.caption).foregroundStyle(Color(Palette.inkMuted)).lineLimit(1)
        }
    }

    private func botCount(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "No bots yet")
        case 1: String(localized: "1 bot")
        default: String(localized: "\(count) bots")
        }
    }

    private func toneColor(_ tone: String?) -> Color? {
        switch tone {
        case "attention": Color(Palette.attention)
        case "negative": Color(Palette.negative)
        case "live": Color(Palette.live)
        case "positive": Color(Palette.positive)
        default: nil
        }
    }

    private func botValue(_ bot: SidebarData.Bots.Item) -> String {
        var parts = [String]()
        if bot.waiting > 0 {
            parts.append(bot.waiting == 1 ? String(localized: "1 decision waiting for you") : String(localized: "\(bot.waiting) decisions waiting for you"))
        } else {
            parts.append(bot.stateLabel)
        }
        if bot.working && bot.state != "working" { parts.append(String(localized: "Working now")) }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func searchResults(_ data: SidebarData) -> some View {
        // The sections' chats come whole with every page; `all=1` adds the rest.
        let pool = (data.sections ?? []).flatMap(\.chats) + (store.everyChat ?? data.chats)
        let found = pool.filter { chat in words.allSatisfy { chat.title.lowercased().contains($0) } }
        if found.isEmpty {
            muted(store.everyChat == nil ? String(localized: "Searching…") : String(localized: "No chats match."))
        } else {
            ForEach(found) { chat in chatRow(chat, pinned: false) }
        }
    }

    private func sectionLabel(_ text: String, top: CGFloat = 10) -> some View {
        Text(text)
            .font(.system(size: captionSize))
            .foregroundStyle(Color(Palette.inkFaint))
            .padding(.horizontal, 10)
            .padding(.top, top)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func chatRow(_ chat: SidebarData.Chat, pinned: Bool) -> some View {
        let current = currentPath.map { AppRoute(path: $0).path == AppRoute(path: chat.url).path } ?? false
        return Button { actions.open(chat.url) } label: {
            HStack(spacing: 10) {
                if pinned {
                    Image(systemName: "bubble.left").font(.system(size: 16)).frame(width: 18, height: 18).foregroundStyle(Color(Palette.inkMuted))
                }
                Text(chat.title)
                    .lineLimit(1)
                    .font(.system(size: rowSize))
                    .foregroundStyle(Color(current ? Palette.ink : Palette.inkMuted))
                Spacer(minLength: 0)
                if chat.isWaiting {
                    Circle().fill(Color(Palette.attention)).frame(width: 7, height: 7)
                        .accessibilityLabel("Waiting for a decision")
                } else if chat.isWorking {
                    Circle().fill(Color(Palette.live)).frame(width: 7, height: 7)
                        .accessibilityLabel("Answering")
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: pinned ? 35 : 38)
            .background(rowBackground(current: current))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(chat.actions ?? []) { action in
                Button(role: action.destructive == true ? .destructive : nil) {
                    actions.perform(action)
                } label: {
                    if let image = action.iosImage {
                        Label(action.title, systemImage: image)
                    } else {
                        Text(action.title)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chat.title)
        .accessibilityValue(chat.isWaiting ? String(localized: "Waiting for a decision") : chat.isWorking ? String(localized: "Answering") : "")
        .accessibilityIdentifier("sidebar.chat")
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Foot

    private func personFooter(_ data: SidebarData) -> some View {
        Menu {
            Section {
                ForEach(data.organizations) { organization in
                    Button {
                        if let url = organization.url { actions.open(url) }
                    } label: {
                        if organization.current == true {
                            Label(organization.name, systemImage: "checkmark")
                        } else {
                            Text(organization.name)
                        }
                    }
                }
                if let all = data.links.organizations, data.organizations.count > 1 {
                    Button { actions.open(all) } label: { Label("All organizations", systemImage: "building.2") }
                }
                if let new = data.links.newOrganization {
                    Button { actions.open(new) } label: { Label("New organization", systemImage: "plus") }
                }
            }
            if let settings = data.links.settings {
                Section {
                    Button { actions.open(settings) } label: { Label("Settings", systemImage: "gearshape") }
                        .accessibilityIdentifier("sidebar.settings")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(data.person.initials)
                    .accessibilityHidden(true)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LinearGradient(colors: [Color(Palette.live), Color(red: 0.48, green: 0.24, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.person.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color(Palette.ink)).lineLimit(1)
                    Text(data.organization.name).font(.caption).foregroundStyle(Color(Palette.inkMuted)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color(Palette.inkMuted))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("sidebar.person")
        .overlay(alignment: .top) { Rectangle().fill(Color(Palette.line)).frame(height: 1) }
    }

    // MARK: Without the list

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer(minLength: 0)
                newButton(name: "New chat", identifier: "sidebar.newChat", isCurrent: false, action: actions.newChat)
            }
            if store.failure == .unavailable {
                Text("Your chats couldn't load. Pull the page or try again.")
                    .font(.footnote)
                    .foregroundStyle(Color(Palette.inkMuted))
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                Button("Try again") { Task { await store.refresh() } }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 8)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
    }

    // MARK: Words

    private func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "·" : String(letters).uppercased()
    }

    private func waitingSymbol(_ kind: String) -> String {
        switch kind {
        case "question": "questionmark.bubble"
        default: "hand.raised"
        }
    }

    private func waitingLabel(_ item: SidebarData.Waiting.Item) -> String {
        // With who asks leading, the line under it says what's to decide.
        if item.asker != nil {
            return [item.summary ?? item.title, item.asker?.project ?? item.project].compactMap { $0 }.joined(separator: " · ")
        }
        let what = switch item.kind {
        case "question": String(localized: "A question for you")
        case "bot": String(localized: "A bot handed it to you")
        default: String(localized: "A change to approve")
        }
        return [what, item.project].compactMap { $0 }.joined(separator: " · ")
    }
}
