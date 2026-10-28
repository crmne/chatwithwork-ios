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

/// The sidebar: the same things in the same order as the web's
/// (chats/_sidebar_chats, application/_me_menu), drawn natively from
/// `/native/sidebar`. Decisions at the top, then the Chats | Bots switch,
/// which list it's about, search, New chat, pins, the person's own sections,
/// the chats in none of them by latest question, and the person at the
/// foot. A long press on a chat opens its menu, as the web row's does.
///
/// Its Bots half keeps the same skeleton, as the web's Bots view does
/// (bots/_sidebar_list): a card opening the Bots page where the list switcher
/// sits, New bot where New chat sits, then the person's bots. A server that
/// sends no `bots.items` gets the Bots row instead of the switch.
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

    var body: some View {
        VStack(spacing: 0) {
            if let data = store.data {
                VStack(spacing: 10) {
                    // Decisions first, just before the switch (or at the top
                    // where there's none), as the web's decisions/_sidebar_button.
                    if let decisions = data.waiting.url ?? data.links.decisions {
                        decisionsButton(count: data.waiting.count, path: decisions)
                    }
                    if store.offersBots, let bots = data.bots {
                        halfSwitch(attention: bots.attention)
                    }
                    if store.showsBots, let bots = data.bots {
                        botsCard(data, bots)
                    } else {
                        listSwitcher(data)
                        searchField
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if store.showsBots, let bots = data.bots {
                            places(data)
                            botsList(bots)
                        } else if query.isEmpty {
                            places(data)
                            chatsList(data)
                        } else {
                            searchResults(data)
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

    // MARK: Top

    private func listSwitcher(_ data: SidebarData) -> some View {
        Menu {
            Section {
                ForEach(data.lists) { list in
                    Button {
                        actions.chooseList(list.key)
                    } label: {
                        if list.key == data.list.key {
                            Label(list.name, systemImage: "checkmark")
                        } else if list.isProject {
                            Label(list.name, systemImage: list.pinned == true ? "pin" : "folder")
                        } else {
                            Text(list.name)
                        }
                    }
                }
            }
            if data.links.projects != nil || data.links.newProject != nil {
                Section {
                    if let projects = data.links.projects {
                        Button { actions.open(projects) } label: { Label("All projects…", systemImage: "folder") }
                    }
                    if let newProject = data.links.newProject {
                        Button { actions.open(newProject) } label: { Label("New project", systemImage: "plus") }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(initials(data.list.name))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(Palette.inkInverted))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.ink)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.list.isProject ? "PROJECT" : "SHOWING")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color(Palette.inkMuted))
                    Text(data.list.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(Palette.ink))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color(Palette.inkMuted))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(Palette.surface)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(Palette.line), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("sidebar.list")
        .accessibilityLabel("Showing \(data.list.name)")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(Palette.inkMuted))
            TextField("Search chats", text: $query)
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
        .font(.subheadline)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(Palette.line).opacity(0.55)))
        .onChange(of: query) { _, value in
            if !value.isEmpty { Task { await store.loadEveryChat() } }
        }
    }

    // MARK: Places

    @ViewBuilder
    private func places(_ data: SidebarData) -> some View {
        if store.showsBots {
            if let newBot = data.bots?.newUrl {
                placeRow("New bot", systemImage: "plus", identifier: "sidebar.newBot") { actions.open(newBot) }
            }
        } else if data.links.newChat != nil {
            placeRow("New chat", systemImage: "square.and.pencil", identifier: "sidebar.newChat", action: actions.newChat)
        }

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
    /// spelled out, and at its end how many wait on the attention wash, or a
    /// quiet "None". While something waits its outline takes the attention
    /// edge, as the web's `.decisions-button` does.
    private func decisionsButton(count: Int, path: String) -> some View {
        let current = currentPath.map { AppRoute(path: $0).path.hasPrefix(AppRoute(path: path).path) } ?? false
        let waits = count > 0
        return Button { actions.open(path) } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Palette.inkMuted))
                    .frame(width: 20)
                Text("Decisions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(Palette.ink))
                Spacer(minLength: 0)
                if waits {
                    Text("\(count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color(Palette.attentionInk))
                        .padding(.horizontal, 7)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Capsule().fill(Color(Palette.attention).opacity(0.16)))
                        .overlay(Capsule().stroke(Color(Palette.attention).opacity(0.45), lineWidth: 1))
                } else {
                    Text("None")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color(Palette.inkFaint))
                        .padding(.trailing, 4)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(current ? Palette.surfaceRaised : Palette.surface)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(waits ? Color(Palette.attention).opacity(0.45) : Color(current ? Palette.lineStrong : Palette.line), lineWidth: 1))
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(Palette.line).opacity(0.55)))
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
            HStack(spacing: 6) {
                icon().frame(width: 16, height: 16).accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .overlay(alignment: .trailing) {
                        if attention {
                            Circle().fill(Color(Palette.attention))
                                .frame(width: 6, height: 6)
                                .offset(x: 10)
                        }
                    }
            }
            .foregroundStyle(Color(chosen ? Palette.ink : Palette.inkMuted))
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(chosen ? Color(Palette.surface) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(chosen ? Color(Palette.lineStrong) : .clear, lineWidth: 0.5))
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
    private func chatsList(_ data: SidebarData) -> some View {
        if !data.pins.isEmpty {
            sectionLabel("Pinned")
            // A pinned chat is also in its day's list: the rows need ids of
            // their own, or the lazy stack leaves a gap where one should be.
            ForEach(data.pins, id: \.pinID) { chat in chatRow(chat, pinned: true) }
        }

        let sections = data.sections ?? []
        ForEach(sections, id: \.rowID) { section in
            sectionHeader(section)
            if !section.collapsed {
                ForEach(section.chats, id: \.sectionRowID) { chat in chatRow(chat, pinned: false) }
            }
        }

        if data.chats.isEmpty {
            if sections.allSatisfy(\.chats.isEmpty) {
                Text(data.list.isProject ? "No chats in this project yet." : "No chats yet.")
                    .font(.footnote)
                    .foregroundStyle(Color(Palette.inkMuted))
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
            }
        } else {
            if sections.isEmpty {
                ForEach(SidebarData.grouped(data.chats), id: \.label) { group in
                    sectionLabel(group.label)
                    ForEach(group.chats) { chat in chatRow(chat, pinned: false) }
                }
            } else {
                // As the web's sidebar: below the sections, the rest under one heading.
                sectionLabel("Other chats")
                ForEach(data.chats) { chat in chatRow(chat, pinned: false) }
            }
            if data.next != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onAppear { Task { await store.loadMore() } }
            }
        }
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
            .padding(.horizontal, 8)
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

    @ViewBuilder
    private func botsList(_ bots: SidebarData.Bots) -> some View {
        let groups = bots.groups
        if groups.isEmpty {
            Text("Your bots, and the ones shared with you, show up here.")
                .font(.footnote)
                .foregroundStyle(Color(Palette.inkMuted))
                .padding(.horizontal, 8)
                .padding(.top, 14)
            if let newBot = bots.newUrl {
                Button { actions.open(newBot) } label: {
                    HStack(spacing: 4) {
                        Text("Start from a recipe")
                        Image(systemName: "arrow.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(Palette.ink))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.recipes")
            }
        } else {
            ForEach(groups, id: \.label) { group in
                if let label = group.label { sectionLabel(label) }
                ForEach(group.items) { bot in botRow(bot) }
            }
        }
    }

    /// One bot: its mark (with a live dot while it works), its name, the
    /// project a shared bot is in, and its state at the end: how many
    /// decisions wait in it, or the state in the web's words.
    private func botRow(_ bot: SidebarData.Bots.Item) -> some View {
        let current = currentPath.map { path in
            let mine = AppRoute(path: bot.url).path
            let here = AppRoute(path: path).path
            return here == mine || here.hasPrefix(mine + "/")
        } ?? false
        return Button { actions.open(bot.url) } label: {
            HStack(spacing: 8) {
                BotMark(size: 18)
                    .foregroundStyle(Color(Palette.ink))
                    .overlay(alignment: .bottomTrailing) {
                        if bot.working {
                            Circle().fill(Color(Palette.live))
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color(Palette.canvasSunken), lineWidth: 1.5))
                                .offset(x: 2, y: 1)
                        }
                    }
                    .frame(width: 20)
                Text(bot.name)
                    .lineLimit(1)
                    .font(.subheadline.weight(current ? .semibold : .regular))
                    .foregroundStyle(Color(Palette.ink))
                if let project = bot.project {
                    Text(project)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundStyle(Color(Palette.inkFaint))
                        .layoutPriority(-1)
                }
                Spacer(minLength: 0)
                if bot.waiting > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(Color(Palette.attention)).frame(width: 7, height: 7)
                        Text("\(bot.waiting)").font(.caption.monospacedDigit()).foregroundStyle(Color(Palette.inkMuted))
                    }
                    .fixedSize()
                } else {
                    stateText(bot.stateLabel, tone: bot.tone)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(current ? Color(Palette.line).opacity(0.7) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bot.project.map { String(localized: "\(bot.name), shared in \($0)") } ?? bot.name)
        .accessibilityValue(botValue(bot))
        .accessibilityIdentifier("sidebar.bot")
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
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
        let words = query.lowercased().split(separator: " ")
        // The sections' chats come whole with every page; `all=1` adds the rest.
        let pool = (data.sections ?? []).flatMap(\.chats) + (store.everyChat ?? data.chats)
        let found = pool.filter { chat in words.allSatisfy { chat.title.lowercased().contains($0) } }
        if found.isEmpty {
            Text(store.everyChat == nil ? "Searching…" : "No chats match.")
                .font(.footnote)
                .foregroundStyle(Color(Palette.inkMuted))
                .padding(.horizontal, 8)
                .padding(.top, 14)
        } else {
            ForEach(found) { chat in chatRow(chat, pinned: false) }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(Palette.inkMuted))
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func chatRow(_ chat: SidebarData.Chat, pinned: Bool) -> some View {
        let current = currentPath.map { AppRoute(path: $0).path == AppRoute(path: chat.url).path } ?? false
        return Button { actions.open(chat.url) } label: {
            HStack(spacing: 8) {
                if pinned {
                    Image(systemName: "pin").font(.caption).foregroundStyle(Color(Palette.inkMuted))
                }
                Text(chat.title)
                    .lineLimit(1)
                    .font(.subheadline.weight(current ? .semibold : .regular))
                    .foregroundStyle(Color(Palette.ink))
                Spacer(minLength: 0)
                if chat.isWaiting {
                    Circle().fill(Color(Palette.attention)).frame(width: 7, height: 7)
                        .accessibilityLabel("Waiting for a decision")
                } else if chat.isWorking {
                    Circle().fill(Color(Palette.live)).frame(width: 7, height: 7)
                        .accessibilityLabel("Answering")
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(current ? Color(Palette.line).opacity(0.7) : .clear))
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
            placeRow("New chat", systemImage: "square.and.pencil", identifier: "sidebar.newChat", action: actions.newChat)
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
