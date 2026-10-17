import SwiftUI
import UniformTypeIdentifiers

enum Destination: String, CaseIterable, Identifiable {
    case library = "Library", playing = "Now Playing", lyrics = "Lyrics Studio", spotify = "Spotify", sound = "Sound Lab", airpods = "AirPods & Output", history = "Listening", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .library: "square.stack.fill"
        case .playing: "waveform"
        case .lyrics: "text.quote"
        case .spotify: "antenna.radiowaves.left.and.right"
        case .sound: "slider.horizontal.3"
        case .airpods: "airpodspro"
        case .history: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination: Destination? = .library
    @State private var importing = false
    @AppStorage("cinematic") private var cinematic = true
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path").font(.title).foregroundStyle(Palette.mint)
                    Text("sonority").font(.system(size: 29, weight: .medium, design: .serif)).tracking(-1)
                }.padding(.horizontal, 20).padding(.top, 24).accessibilityElement(children: .combine)
                Text("YOUR WORLD. IN SOUND.").font(.system(size: 9, weight: .semibold)).tracking(2.5).foregroundStyle(.secondary).padding(.horizontal, 22)
                List(Destination.allCases, selection: $destination) { item in Label(item.rawValue, systemImage: item.icon).tag(item).padding(.vertical, 6) }
                    .listStyle(.sidebar).scrollContentBackground(.hidden)
                VStack(alignment: .leading, spacing: 10) {
                    Label("On your iPad", systemImage: "internaldrive").foregroundStyle(Palette.mint)
                    Text("\(library.library.tracks.count) tracks · always yours").font(.caption).foregroundStyle(.secondary)
                    Button { importing = true } label: { Label(library.importing ? "Importing…" : "Import music", systemImage: "plus") }.disabled(library.importing || library.recoveryRequired)
                }.padding(22)
            }.background(Palette.charcoal).navigationSplitViewColumnWidth(min: 230, ideal: 255, max: 290)
        } detail: {
            ZStack {
                Palette.charcoal.ignoresSafeArea()
                if cinematic {
                    RadialGradient(colors: [Palette.forest.opacity(0.4), .clear], center: .topTrailing, startRadius: 10, endRadius: 700).ignoresSafeArea()
                }
                Group {
                    switch destination ?? .library {
                    case .library: LibraryView(importing: $importing)
                    case .playing: NowPlayingView()
                    case .lyrics: LyricsView()
                    case .spotify: SpotifyView()
                    case .sound: SoundLabView()
                    case .airpods: OutputView()
                    case .history: ListeningView()
                    case .settings: SettingsView()
                    }
                }
            }
            .navigationTitle((destination ?? .library).rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { importing = true } label: { Image(systemName: "plus.circle") }.accessibilityLabel("Import music").disabled(library.importing || library.recoveryRequired) } }
            .safeAreaInset(edge: .bottom) {
                if player.current != nil {
                    MiniPlayer { destination = .playing }.padding(.horizontal, 18).padding(.bottom, 8)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): Task { await library.importAudio(urls) }; case .failure(let error): library.message = error.localizedDescription }
        }
        .alert("Library", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) { Button("OK") { library.message = nil } } message: { Text(library.message ?? "") }
        .alert("Playback", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) { Button("OK") { player.error = nil } } message: { Text(player.error ?? "") }
        .onOpenURL { url in
            guard url.scheme == "sonority" else { return }
            if url.host == "import" { importing = true; destination = .library }
            else if url.host == "lyrics" { destination = .lyrics }
            else if url.host == "playing" { destination = .playing }
            else { destination = .library }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { player.checkpoint(); library.save() }
            if phase == .active { player.refreshRoute() }
        }
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    var open: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 14) {
                    Artwork(image: library.artwork(player.current), radius: 10).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.current?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(player.current?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open Now Playing")
            Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Next track")
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(alignment: .bottomLeading) { GeometryReader { proxy in Capsule().fill(Palette.mint).frame(width: proxy.size.width * min(1, player.position / max(1, player.duration)), height: 2) }.frame(height: 2).padding(.horizontal, 20) }
    }
}
