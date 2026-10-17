import SwiftUI
import SonorityCore

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Binding var importing: Bool
    @State private var query = ""
    @State private var grouping = "Tracks"
    @State private var favorites = false
    @State private var playlistID: UUID?
    @State private var creatingPlaylist = false
    @State private var playlistName = ""
    @State private var deleting: Track?
    private var filtered: [Track] {
        let playlist = library.library.playlists.first { $0.id == playlistID }
        let tracks: [Track] = playlist.map { list in list.trackIDs.compactMap { library.track($0) } } ?? library.library.tracks
        return tracks.filter { track in
            (!favorites || track.favorite) && (query.isEmpty || "\(track.title) \(track.artist) \(track.album)".localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SectionHeading(eyebrow: "A space for your sound", title: "Stay a little longer.", subtitle: "Your collection, beautifully in tune.")
                if library.library.tracks.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack { Image(systemName: "opticaldisc").font(.system(size: 70, weight: .ultraLight)); Spacer(); Text("01 /\nTHE BEGINNING").font(.caption.monospaced()).foregroundStyle(Palette.mint) }
                        Text("Great listening\nstarts here.").font(.system(.largeTitle, design: .serif))
                        Text("Bring your own music. Import MP3, AAC, ALAC, WAV, AIFF, or another format your iPad can decode. Files are copied to Sonority for offline listening.").foregroundStyle(.secondary).frame(maxWidth: 520, alignment: .leading)
                        Button { importing = true } label: { Label("Import your first tracks", systemImage: "plus").padding(8) }.buttonStyle(.borderedProminent).disabled(library.importing || library.recoveryRequired)
                    }.padding(34).frame(maxWidth: .infinity, alignment: .leading).background(LinearGradient(colors: [Palette.forest, Palette.charcoal], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 30))
                } else {
                    HStack {
                        Label("\(library.library.tracks.count) tracks", systemImage: "music.note")
                        Spacer()
                        Text("\(Set(library.library.tracks.map(\.artist)).count) artists").foregroundStyle(.secondary)
                    }.font(.subheadline).panel()
                    ViewThatFits(in: .horizontal) {
                        HStack { filters; Spacer(); playlistMenu }
                        VStack(alignment: .leading, spacing: 16) { filters; playlistMenu }
                    }
                    if grouping == "Tracks" || playlistID != nil {
                        LazyVStack(spacing: 2) { ForEach(filtered) { track in trackRow(track) } }
                    } else {
                        let groups = Dictionary(grouping: filtered, by: { grouping == "Albums" ? "\($0.album) · \($0.artist)" : $0.artist })
                        ForEach(groups.keys.sorted(), id: \.self) { key in
                            DisclosureGroup {
                                ForEach(groups[key] ?? []) { track in trackRow(track) }
                            } label: {
                                HStack(spacing: 16) {
                                    Artwork(image: library.artwork(groups[key]?.first)).frame(width: 76, height: 76)
                                    VStack(alignment: .leading, spacing: 6) { Text(key).font(.headline); Text("\(groups[key]?.count ?? 0) tracks").font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical, 10)
                            }.tint(Palette.mint)
                        }
                    }
                    if filtered.isEmpty { ContentUnavailableView.search(text: query) }
                }
                if library.importing { ProgressView("Copying and reading your music…").padding() }
            }.padding(28).frame(maxWidth: 1200)
        }.searchable(text: $query, prompt: "Tracks, artists, albums")
        .alert("New playlist", isPresented: $creatingPlaylist) {
            TextField("Playlist name", text: $playlistName)
            Button("Create") { library.createPlaylist(playlistName); playlistName = "" }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove \(deleting?.title ?? "track") from Sonority?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Remove imported copy", role: .destructive) {
                if let track = deleting { if player.current?.id == track.id { player.stop() }; library.deleteTrack(track.id) }
                deleting = nil
            }
        } message: { Text("The original in Files is unaffected.") }
    }
    private var filters: some View {
        HStack(spacing: 16) {
            Picker("Group library", selection: $grouping) { ForEach(["Tracks", "Albums", "Artists"], id: \.self) { Text($0) } }.pickerStyle(.menu)
            Toggle(isOn: $favorites) { Label("Favorites", systemImage: "heart.fill") }.toggleStyle(.button)
        }
    }
    private var playlistMenu: some View {
        Menu {
            Button("All music") { playlistID = nil }
            ForEach(library.library.playlists) { list in Button(list.name) { playlistID = list.id } }
            Divider()
            Button("New playlist", systemImage: "plus") { creatingPlaylist = true }
            if let id = playlistID {
                Button("Delete playlist", role: .destructive) { library.deletePlaylist(id); playlistID = nil }
            }
        } label: { Label(library.library.playlists.first(where: { $0.id == playlistID })?.name ?? "All music", systemImage: "music.note.list") }
    }
    private func trackRow(_ track: Track) -> some View {
        HStack(spacing: 14) {
            Button { player.play(track, in: filtered) } label: {
                HStack(spacing: 14) {
                    Artwork(image: library.artwork(track), radius: 10).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.subheadline.weight(.medium)).foregroundStyle(player.current?.id == track.id ? Palette.mint : .white)
                        Text("\(track.artist) · \(track.album)").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(clockTime(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button(track.favorite ? "Remove favorite" : "Favorite", systemImage: track.favorite ? "heart.slash" : "heart") { library.toggleFavorite(track.id) }
                Button("Add to queue", systemImage: "text.line.last.and.arrowtriangle.forward") { player.enqueue(track.id) }
                Menu("Add to playlist") { ForEach(library.library.playlists) { list in Button(list.name) { library.add(track.id, to: list.id) } } }
                if let id = playlistID { Button("Remove from playlist") { library.removeFromPlaylist(track.id, playlist: id) } }
                Button("Remove from library", role: .destructive) { deleting = track }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(track.title)")
        }.padding(10).background(player.current?.id == track.id ? Palette.forest.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 15))
    }
}
