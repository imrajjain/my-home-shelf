import SwiftUI
import ShelfCore

/// Flags & Anthems: every country's flag flying on the wall, its anthem a
/// click away, and the rest of the world in a drawer below.
struct FlagsMuseumView: View {
    @AppStorage("museum.flags.current") private var currentID = ""
    @State private var region: String?
    @State private var query = ""
    @State private var player = AnthemPlayer.shared

    private let flags = NationalFlags.all

    private var current: NationalFlag? {
        flags.first { $0.id == currentID } ?? flags.first { $0.id == "in" } ?? flags.first
    }

    var body: some View {
        ZStack {
            Gallery.wall.ignoresSafeArea()
            if let current {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        FlagStage(flag: current)
                            .id(current.id)
                            .transition(.opacity)
                            .overlay(alignment: .bottom) { controls(current) }
                        FlagPlacard(flag: current, player: player)
                            .frame(width: 330)
                            .padding(.trailing, 24)
                            .padding(.vertical, 24)
                    }
                    drawer(current)
                }
            } else {
                ContentUnavailableView("The flags are on their way", systemImage: "flag",
                                       description: Text("Shelf couldn’t find its flag collection."))
            }
        }
        .background(KeyCatcher(left: { step(-1) }, right: { step(1) }, space: { if let current { player.toggle(current) } }))
        .onDisappear { player.stop() }
    }

    // MARK: Pieces

    private func controls(_ flag: NationalFlag) -> some View {
        HStack(spacing: 14) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous country (←)")
            if flag.anthem?.recording != nil {
                Button { player.toggle(flag) } label: {
                    Label(player.isPlaying(flag) ? "Stop Anthem" : (player.loadingID == flag.id ? "Loading…" : "Play Anthem"),
                          systemImage: player.isPlaying(flag) ? "stop.fill" : "play.fill")
                }
                .help("Play or stop the anthem (Space)")
            }
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .help("Next country (→)")
        }
        .buttonStyle(.pillGlass)
        .padding(.bottom, 18)
    }

    private func drawer(_ current: NationalFlag) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                chip(nil, "All")
                ForEach(NationalFlags.regions, id: \.self) { chip($0, $0) }
                Spacer()
                TextField("Find a country", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Text("\(flags.count) countries")
                    .font(.system(size: 11))
                    .foregroundStyle(Gallery.faint)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(visible) { flag in
                            DrawerFlag(flag: flag, selected: flag.id == current.id) { select(flag) }
                                .id(flag.id)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .frame(height: 84)
                .onAppear { proxy.scrollTo(current.id, anchor: .center) }
                .onChange(of: currentID) { _, id in withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Gallery.drawer)
        .overlay(alignment: .top) { Rectangle().fill(Gallery.rule).frame(height: 1) }
    }

    private func chip(_ value: String?, _ title: String) -> some View {
        Button(title) { withAnimation(.smooth) { region = value } }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: region == value ? .semibold : .regular))
            .foregroundStyle(region == value ? Gallery.ink : Gallery.faint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(region == value ? Gallery.chip : .clear, in: Capsule())
    }

    private var visible: [NationalFlag] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return flags.filter { flag in
            (region == nil || flag.region == region)
                && (q.isEmpty || flag.country.localizedCaseInsensitiveContains(q)
                    || (flag.anthem?.title?.localizedCaseInsensitiveContains(q) ?? false))
        }
    }

    // MARK: Moving around

    private func select(_ flag: NationalFlag) {
        if !player.isPlaying(flag) { player.stop() }
        withAnimation(.smooth(duration: 0.4)) { currentID = flag.id }
    }

    private func step(_ delta: Int) {
        let list = visible.isEmpty ? flags : visible
        let index = list.firstIndex { $0.id == current?.id } ?? 0
        select(list[(index + delta + list.count) % list.count])
    }
}

/// The label: the flag's story, then the anthem's.
private struct FlagPlacard: View {
    let flag: NationalFlag
    let player: AnthemPlayer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(flag.region.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(Gallery.faint)
                    Text(flag.country)
                        .font(.display(28, weight: .regular))
                        .foregroundStyle(Gallery.ink)
                }

                section("The flag", flag.flagAbout, link: ("Read about the \(flag.flagTitle.lowercased().hasPrefix("flag") ? "flag" : flag.flagTitle)", flag.flagSource))

                if let anthem = flag.anthem {
                    anthemSection(anthem)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Flag: \(flag.flag.credit)").lineLimit(2)
                    if let recording = flag.anthem?.recording {
                        Text("Recording: \(recording.credit.isEmpty ? "Wikimedia Commons" : recording.credit)").lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Link("Flag image", destination: flag.flag.page)
                        if let recording = flag.anthem?.recording { Link("Recording", destination: recording.page) }
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Gallery.faint)
            }
            .padding(22)
        }
        .scrollIndicators(.never)
        .tint(Gallery.ink)
        .opensWikipediaInReader()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Gallery.rule))
    }

    private func anthemSection(_ anthem: NationalFlag.Anthem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE ANTHEM")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Gallery.faint)
            HStack(alignment: .center, spacing: 12) {
                if anthem.recording != nil {
                    Button { player.toggle(flag) } label: {
                        ZStack {
                            Circle().fill(Gallery.chip)
                            if player.loadingID == flag.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: player.isPlaying(flag) ? "stop.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Gallery.ink)
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(player.isPlaying(flag) ? "Stop" : "Play the anthem")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(anthem.title ?? "National anthem")
                        .font(.display(17))
                        .foregroundStyle(Gallery.ink)
                    if let people = credits(anthem) {
                        Text(people).font(.system(size: 11.5)).foregroundStyle(Gallery.soft)
                    }
                }
            }
            if player.isPlaying(flag) {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    ProgressLine(value: player.progress)
                }
                .transition(.opacity)
            }
            if anthem.recording == nil {
                Text("No freely licensed recording of this anthem is available yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Gallery.faint)
            } else if player.failedID == flag.id {
                Text("Couldn’t load the recording. Check your connection and try again.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Gallery.faint)
            }
            if !anthem.about.isEmpty {
                Text(anthem.about)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Gallery.ink.opacity(0.88))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let source = anthem.source {
                Link("Read about the anthem", destination: source).font(.system(size: 11.5))
            }
        }
        .animation(.smooth, value: player.playingID)
    }

    private func credits(_ anthem: NationalFlag.Anthem) -> String? {
        var parts: [String] = []
        if !anthem.composers.isEmpty { parts.append("Music: " + ListFormatter.localizedString(byJoining: anthem.composers)) }
        if !anthem.lyricists.isEmpty { parts.append("Words: " + ListFormatter.localizedString(byJoining: anthem.lyricists)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func section(_ title: String, _ text: String, link: (String, URL)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Gallery.faint)
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Gallery.ink.opacity(0.88))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Link(link.0, destination: link.1).font(.system(size: 11.5))
        }
    }
}

private struct DrawerFlag: View {
    let flag: NationalFlag
    let selected: Bool
    let select: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Gallery.chip)
                    if let image {
                        Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
                    } else {
                        Text(flag.emoji).font(.system(size: 22))
                    }
                }
                .frame(width: 66, height: 44)
                .shadow(color: .black.opacity(hovering || selected ? 0.25 : 0.1), radius: hovering ? 5 : 2, y: 1)
                .offset(y: hovering && !selected ? -2 : 0)
                Text(flag.country)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Gallery.ink : Gallery.soft)
                    .lineLimit(1)
                    .frame(width: 76)
            }
            .padding(5)
            .background(selected ? Gallery.chip : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.lift) { hovering = inside } }
        .help(flag.country)
        .task { image = await BanknoteImages.shared.image(flag.flag.thumb) }
    }
}
