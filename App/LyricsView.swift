import SwiftUI
import UniformTypeIdentifiers
import SonorityCore

struct LyricsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cleanLyrics") private var clean = false
    @State private var importing = false
    @State private var translation = false
    @State private var fullscreen = false
    @State private var follow = true
    @State private var document = LyricsDocument()
    private var active: Int? { document.activeIndex(at: player.position) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text(player.current?.title ?? "Lyrics Studio").font(.headline); Text(player.current?.artist ?? "Words, with room to breathe.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Toggle("Follow", isOn: $follow).toggleStyle(.button)
                Menu {
                    Toggle("Clean reading mode", isOn: $clean)
                    Button("Import original LRC or text") { translation = false; importing = true }.disabled(player.current == nil)
                    Button("Import translation LRC") { translation = true; importing = true }.disabled(player.current == nil)
                    Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { fullscreen = true }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Lyrics options")
            }.padding(24)
            lyricsBody
            Text("Embedded or user-imported lyrics · tap a timed line to seek").font(.caption).foregroundStyle(.secondary).padding(16)
        }.fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]) { result in
            if case .success(let url) = result, let track = player.current { library.importLyrics(url, track: track, translation: translation); reload() }
            else if case .failure(let error) = result { library.message = error.localizedDescription }
        }
        .task(id: player.current?.id) { reload() }
        .fullScreenCover(isPresented: $fullscreen) {
            ZStack(alignment: .topTrailing) {
                Palette.charcoal.ignoresSafeArea(); lyricsBody.padding(.top, 60)
                Button { fullscreen = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(.regularMaterial, in: Circle()) }.accessibilityLabel("Close full screen lyrics").padding(24)
            }.preferredColorScheme(.dark)
        }
    }
    private var lyricsBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: clean ? 22 : 36) {
                    if document.lines.isEmpty {
                        if let text = document.plainText, !text.isEmpty { Text(text).font(.system(clean ? .title3 : .title, design: clean ? .default : .serif)).lineSpacing(14).textSelection(.enabled) }
                        else {
                            ContentUnavailableView("Let the words in.", systemImage: "text.quote", description: Text("Play a local track, then import its LRC file. Import a second timestamped LRC to display a translation alongside the original. Online lyrics need a licensed provider and are not connected."))
                        }
                    } else {
                        ForEach(document.lines) { line in
                            Button { player.seek(line.time) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(line.text.isEmpty ? "♪" : line.text).font(.system(clean ? .title2 : .largeTitle, design: clean ? .default : .serif, weight: active == line.id ? .semibold : .regular))
                                    if let translated = line.translation { Text(translated).font(.title3).foregroundStyle(.secondary) }
                                }.foregroundStyle(clean || active == line.id ? Color.white : Color.white.opacity(0.4)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).id(line.id).accessibilityLabel("\(line.text), at \(clockTime(line.time))").accessibilityHint("Seek to this line")
                        }
                    }
                }.padding(.horizontal, clean ? 28 : 40).padding(.vertical, 60).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }.onChange(of: active) { _, index in
                guard follow, let index else { return }
                if reduceMotion { proxy.scrollTo(index, anchor: .center) }
                else { withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(index, anchor: .center) } }
            }
        }
    }
    private func reload() { document = player.current.map { library.lyrics(for: $0) } ?? LyricsDocument() }
}
