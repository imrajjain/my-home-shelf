import SwiftUI
import ShelfCore

/// Find people by username, answer friend requests, see who you follow.
struct PeopleView: View {
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var results: [PublicProfile] = []
    @State private var searching = false
    private var friends = FriendsList.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("People").font(.display(28, weight: .regular)).foregroundStyle(Color.ink)
                    Text("Follow someone to see what they share with everyone. Become friends to see what they share with friends.")
                        .font(.system(size: 13)).foregroundStyle(Color.inkSoft)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.inkFaint)
                    TextField("Search by username", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await search() } }
                        .onChange(of: query) { _, _ in Task { try? await Task.sleep(for: .milliseconds(350)); await search() } }
                    if searching { ProgressView().controlSize(.small) }
                }
                .padding(10)
                .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.hairline))

                if !results.isEmpty {
                    section("Results") { ForEach(results) { personRow($0.username, $0.displayName, note: nil) } }
                }
                if !friends.requests.isEmpty {
                    section("Friend requests") {
                        ForEach(friends.requests) { p in
                            HStack {
                                personRow(p.username, p.displayName, note: "wants to be friends")
                                Button("Accept") { Task { _ = try? await CloudAPI.friend(p.username, true); await friends.refresh() } }
                                    .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
                                Button("Decline") { Task { _ = try? await CloudAPI.friend(p.username, false); await friends.refresh() } }
                                    .buttonStyle(.pillCompact)
                            }
                        }
                    }
                }
                let mutual = friends.people.filter { $0.friend == "friends" }
                let followed = friends.people.filter { $0.friend != "friends" && $0.following }
                if !mutual.isEmpty {
                    section("Friends") { ForEach(mutual) { personRow($0.username, $0.displayName, note: nil) } }
                }
                if !followed.isEmpty {
                    section("Following") {
                        ForEach(followed) { personRow($0.username, $0.displayName, note: $0.friend == "requested" ? "friend request sent" : nil) }
                    }
                }
                if mutual.isEmpty && followed.isEmpty && friends.requests.isEmpty && results.isEmpty {
                    EmptyShelf(symbol: "person.2", title: "No one here yet",
                               message: "Search for a friend's username, or share yours from Settings ▸ Account.")
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await friends.refresh() }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(title)
            content()
        }
    }

    private func personRow(_ username: String, _ name: String, note: String?) -> some View {
        Button { router.selection = .person(username) } label: {
            HStack(spacing: 12) {
                Avatar(name: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.ink)
                    Text("@\(username)" + (note.map { " · \($0)" } ?? "")).font(.system(size: 12)).foregroundStyle(Color.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.inkFaint)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        searching = true
        results = (try? await CloudAPI.search(q)) ?? []
        searching = false
    }
}

/// A person's initials on a soft disc.
struct Avatar: View {
    let name: String
    var size: CGFloat = 34

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        Circle()
            .fill(Color.accentWashStrong)
            .frame(width: size, height: size)
            .overlay(Text(initials.isEmpty ? "?" : initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(Color.ink))
    }
}

/// Someone's shared shelf: their profile, and what they've let you see.
struct PersonShelfView: View {
    let username: String
    let mine: [Item]
    @State private var shelf: PersonShelf?
    @State private var error: String?
    @State private var busy = false
    @State private var added: Set<UUID> = []

    var body: some View {
        ScrollView {
            if let shelf {
                VStack(alignment: .leading, spacing: 26) {
                    header(shelf)
                    if shelf.items.isEmpty {
                        EmptyShelf(symbol: "lock", title: "Nothing shared with you yet",
                                   message: shelf.friend == "friends"
                                   ? "\(shelf.profile.displayName) hasn't shared anything with friends."
                                   : "Become friends to see more than what they share with everyone.")
                            .frame(maxWidth: .infinity).padding(.top, 30)
                    } else {
                        ForEach(kinds(shelf.items), id: \.self) { kind in
                            let list = shelf.items.filter { $0.kind == kind }
                            VStack(alignment: .leading, spacing: 4) {
                                SectionHeader(title: kind.pluralTitle, note: "\(list.count)")
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 20, alignment: .top)], alignment: .leading, spacing: 22) {
                                    ForEach(list) { record in card(record) }
                                }
                            }
                        }
                    }
                }
                .padding(40)
            } else if let error {
                EmptyShelf(symbol: "person.crop.circle.badge.questionmark", title: "Couldn't open @\(username)", message: error)
                    .frame(maxWidth: .infinity).padding(.top, 80)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
            }
        }
        .task { await load() }
    }

    private func header(_ s: PersonShelf) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Avatar(name: s.profile.displayName, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.profile.displayName).font(.display(26, weight: .regular)).foregroundStyle(Color.ink)
                Text("@\(s.profile.username)").font(.system(size: 13)).foregroundStyle(Color.inkSoft)
                if let bio = s.profile.bio, !bio.isEmpty {
                    Text(bio).font(.system(size: 13)).foregroundStyle(Color.inkSoft).padding(.top, 2)
                }
            }
            Spacer()
            if s.relation != "owner" {
                HStack(spacing: 8) {
                    Button(s.following ? "Following" : "Follow", systemImage: s.following ? "checkmark" : "plus") {
                        act { try await CloudAPI.follow(username, !s.following) }
                    }
                    .buttonStyle(s.following ? PillButtonStyle(kind: .secondary, compact: true) : PillButtonStyle(kind: .primary, compact: true))
                    friendButton(s)
                }
                .disabled(busy)
            }
        }
    }

    @ViewBuilder private func friendButton(_ s: PersonShelf) -> some View {
        switch s.friend {
        case "friends":
            Menu("Friends", systemImage: "person.2.fill") {
                Button("Remove Friend", role: .destructive) { act { _ = try await CloudAPI.friend(username, false) } }
            }
            .menuStyle(.button).buttonStyle(.pillCompact).fixedSize()
        case "requested":
            Button("Request Sent", systemImage: "clock") { act { _ = try await CloudAPI.friend(username, false) } }
                .buttonStyle(.pillCompact).help("Click to cancel the request")
        case "incoming":
            Button("Accept Friend", systemImage: "person.badge.plus") { act { _ = try await CloudAPI.friend(username, true) } }
                .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
        default:
            Button("Add Friend", systemImage: "person.badge.plus") { act { _ = try await CloudAPI.friend(username, true) } }
                .buttonStyle(.pillCompact)
        }
    }

    private func card(_ record: ItemRecord) -> some View {
        let have = added.contains(record.id) || mine.contains { $0.title.caseInsensitiveCompare(record.title) == .orderedSame && $0.kind == record.kind }
        return VStack(alignment: .leading, spacing: 6) {
            CoverView(kind: record.kind, title: record.title, creator: record.creator, imageURL: record.imageURL, cornerRadius: 6)
                .frame(width: 120)
                .overlay(alignment: .topTrailing) {
                    if record.status == .done {
                        Image(systemName: "checkmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(.black.opacity(0.45), in: Circle()).padding(6)
                    }
                }
            Text(record.title).font(.cardTitle).foregroundStyle(Color.ink).lineLimit(2, reservesSpace: true)
            Button(have ? "On your shelf" : "Add to My Shelf", systemImage: have ? "checkmark" : "plus") { add(record) }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(have ? Color.inkFaint : Color.accent)
                .disabled(have)
        }
        .frame(width: 120, alignment: .leading)
        .contextMenu {
            if let url = record.url { Button("Open Link") { NSWorkspace.shared.open(url) } }
        }
    }

    private func add(_ record: ItemRecord) {
        let item = Item(kind: record.kind, status: .want, title: record.title)
        item.subtitle = record.subtitle; item.creator = record.creator; item.year = record.year
        item.summary = record.summary; item.urlString = record.url?.absoluteString
        item.imageURLString = record.imageURL?.absoluteString; item.tags = record.tags
        item.extra["recommendedBy"] = username
        Persistence.context.insert(item)
        try? Persistence.context.save()
        added.insert(record.id)
        if let url = record.imageURL { Task { if let data = await ImageCache.download(url) { item.imageData = data } } }
    }

    private func kinds(_ items: [ItemRecord]) -> [ItemKind] {
        ItemKind.allCases.filter { k in items.contains { $0.kind == k } }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await work() } catch { self.error = error.localizedDescription }
            await load()
            await FriendsList.shared.refresh()
            busy = false
        }
    }

    private func load() async {
        do { shelf = try await CloudAPI.person(username); error = nil }
        catch { if shelf == nil { self.error = error.localizedDescription } }
    }
}
