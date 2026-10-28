import SwiftUI
import ShelfCore

/// Settings ▸ Account: sign in, your username, backup, and what each shelf
/// shares by default.
struct AccountSettings: View {
    private var account = Account.shared
    private var sync = CloudSync.shared
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var copied = false

    var body: some View {
        Form {
            switch account.state {
            case .signedOut:
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Back up your shelf and share it with friends")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Signing in is optional. Your shelf stays on this Mac either way; signing in also keeps a copy in Shelf's cloud and lets friends see what you choose to share. Everything is private until you say otherwise.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Sign In or Create Account…") { Task { await account.signIn() } }
                            .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            case .unreachable(let why):
                Section {
                    Text("Couldn't reach Shelf's cloud: \(why)").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button("Try Again") { Task { await account.refresh() } }
                        Spacer()
                        Button("Sign Out", role: .destructive) { account.signOut() }
                    }
                }
            case .checking:
                Section { HStack { ProgressView().controlSize(.small); Text("Signing in…") } }
            case .needsUsername:
                Section("Choose your username") {
                    TextField("Username", text: $username, prompt: Text("Choose a username"))
                    TextField("Display name", text: $displayName, prompt: Text("Your name"))
                    Text("3–20 letters, numbers or underscores. Friends find you by it, and it's in your profile link.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Sign Out", role: .cancel) { account.signOut() }
                        Spacer()
                        Button("Save") { Task { _ = await account.save(username: username, displayName: displayName) } }
                            .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
                            .disabled(username.count < 3)
                    }
                }
            case .signedIn(let profile):
                Section("Profile") {
                    LabeledContent("Username", value: "@\(profile.username)")
                    TextField("Display name", text: $displayName)
                    TextField("Bio", text: $bio, prompt: Text("What you're into, in a line"), axis: .vertical)
                        .lineLimit(1...3)
                    HStack {
                        Button(copied ? "Copied" : "Copy Profile Link", systemImage: copied ? "checkmark" : "link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(CloudConfig.profileURL(profile.username).absoluteString, forType: .string)
                            copied = true
                        }
                        Spacer()
                        Button("Save") { Task { _ = await account.save(username: profile.username, displayName: displayName, bio: bio) } }
                            .disabled(displayName == profile.displayName && bio == (profile.bio ?? ""))
                    }
                }
                Section("Backup") {
                    LabeledContent("Status", value: statusText)
                    HStack {
                        Button("Back Up Now") { Task { await sync.run() } }
                        Spacer()
                        Button("Sign Out", role: .destructive) { account.signOut() }
                    }
                }
                Section {
                    ForEach(ItemKind.allCases) { kind in
                        Picker(kind.pluralTitle, selection: Binding(
                            get: { Sharing.shelfDefault(kind) },
                            set: { Sharing.setShelfDefault($0, for: kind) }
                        )) {
                            ForEach(Visibility.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    }
                } header: {
                    Text("Who can see each shelf")
                } footer: {
                    Text("Friends see Friends and Everyone; followers and your public page see Everyone only. Any item can override its shelf in its details. Notes, ratings and progress are never shared.")
                }
            }
            if let error = account.error {
                Section { Text(error).foregroundStyle(.red).font(.caption) }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: fill)
        .onChange(of: account.state) { _, _ in fill() }
    }

    private var statusText: String {
        switch sync.status {
        case .idle: "Waiting"
        case .syncing: "Backing up…"
        case .synced(let date): "Backed up \(date.formatted(.relative(presentation: .named)))"
        case .failed(let why): "Couldn't back up: \(why)"
        }
    }

    private func fill() {
        if let p = account.profile {
            displayName = p.displayName
            bio = p.bio ?? ""
        }
    }
}

/// "Shared with" for one item, defaulting to its shelf.
struct SharingPicker: View {
    let item: Item

    var body: some View {
        let current = Sharing.override(of: item)
        Menu {
            Button {
                Sharing.setOverride(nil, for: item)
            } label: {
                Label("Same as \(item.kind.pluralTitle) (\(Sharing.shelfDefault(item.kind).title))",
                      systemImage: current == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(Visibility.allCases) { v in
                Button { Sharing.setOverride(v, for: item) } label: {
                    Label(v.title, systemImage: current == v ? "checkmark" : v.symbol)
                }
            }
        } label: {
            Label(Sharing.visibility(of: item).title, systemImage: Sharing.visibility(of: item).symbol)
        }
        .menuStyle(.button)
        .buttonStyle(.pillCompact)
        .fixedSize()
        .help("Who can see this")
    }
}

/// Home: what friends and the people you follow finished lately.
struct FriendsFeedRow: View {
    @Environment(Router.self) private var router
    private var friends = FriendsList.shared

    var body: some View {
        if Account.shared.isSignedIn, !friends.feed.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: "Friends finished", action: { router.selection = .people })
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 20) {
                        ForEach(friends.feed.prefix(16)) { entry in
                            Button { router.selection = .person(entry.person.username) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    CoverView(kind: entry.item.kind, title: entry.item.title, creator: entry.item.creator,
                                              imageURL: entry.item.imageURL, cornerRadius: 6)
                                        .frame(width: 104)
                                    Text(entry.item.title).font(.cardTitle).foregroundStyle(Color.ink).lineLimit(2, reservesSpace: true)
                                    Text(entry.person.displayName).font(.cardDetail).foregroundStyle(Color.inkFaint).lineLimit(1)
                                }
                                .frame(width: 104, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, -4)
            }
        }
    }
}
