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
}

/// The sidebar: the same things in the same order as the web's
/// (chats/_sidebar_chats, application/_me_menu), drawn natively from
/// `/native/sidebar`. Which list it's about at the top, search, New chat,
/// Decisions (what waits for the person), Bots, pins, the chats by latest
/// question, and the person at the foot. A long press on a chat opens its
/// menu, as the web row's does.
struct SidebarView: View {
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
                    listSwitcher(data)
                    searchField
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if query.isEmpty {
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
        if data.links.newChat != nil {
            placeRow("New chat", systemImage: "square.and.pencil", identifier: "sidebar.newChat", action: actions.newChat)
        }

        // Decisions, named as on the web. It opens the Decisions page, which
        // works through them one at a time; a server without one sends no
        // url, and the row lists what waits instead.
        placeRow("Decisions", systemImage: "hand.raised", identifier: "sidebar.waiting", trailing: {
            if data.waiting.count > 0 {
                HStack(spacing: 5) {
                    Circle().fill(Color(Palette.attention)).frame(width: 7, height: 7)
                    Text("\(data.waiting.count)").font(.caption.monospacedDigit()).foregroundStyle(Color(Palette.inkMuted))
                }
            }
        }) {
            if let decisions = data.waiting.url ?? data.links.decisions {
                actions.open(decisions)
            } else {
                withAnimation(.snappy) { showsWaiting.toggle() }
            }
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
                                Text(item.title).lineLimit(1).foregroundStyle(Color(Palette.ink))
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

        if let bots = data.links.bots {
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

        if data.chats.isEmpty {
            Text(data.list.isProject ? "No chats in this project yet." : "No chats yet.")
                .font(.footnote)
                .foregroundStyle(Color(Palette.inkMuted))
                .padding(.horizontal, 8)
                .padding(.top, 14)
        } else {
            ForEach(SidebarData.grouped(data.chats), id: \.label) { group in
                sectionLabel(group.label)
                ForEach(group.chats) { chat in chatRow(chat, pinned: false) }
            }
            if data.next != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onAppear { Task { await store.loadMore() } }
            }
        }
    }

    @ViewBuilder
    private func searchResults(_ data: SidebarData) -> some View {
        let words = query.lowercased().split(separator: " ")
        let pool = store.everyChat ?? data.chats
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
        let what = switch item.kind {
        case "question": String(localized: "A question for you")
        case "bot": String(localized: "A bot handed it to you")
        default: String(localized: "A change to approve")
        }
        return [what, item.project].compactMap { $0 }.joined(separator: " · ")
    }
}
