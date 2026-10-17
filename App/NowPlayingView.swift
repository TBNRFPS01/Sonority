import SwiftUI
import SonorityCore

struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var queueShown = false
    @State private var dragging = false
    @State private var scrub = 0.0
    @State private var atmosphere = Palette.forest
    @AppStorage("cinematic") private var cinematic = true
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let track = player.current {
                    VStack(spacing: 32) {
                        SectionHeading(eyebrow: "Now playing · local audio", title: "Just you and the music.", subtitle: track.album)
                        if geometry.size.width > 850 {
                            HStack(alignment: .center, spacing: 56) { cover(track).frame(maxWidth: 470); controls(track).frame(maxWidth: 450) }
                        } else {
                            cover(track).frame(maxWidth: 430); controls(track).frame(maxWidth: 550)
                        }
                        HStack { Label(player.routeName.isEmpty ? "System output" : player.routeName, systemImage: "hifispeaker").font(.caption).foregroundStyle(.secondary); RoutePicker().frame(width: 44, height: 44); Spacer(); Button { queueShown = true } label: { Label("Queue · \(player.queue.ids.count)", systemImage: "list.bullet") } }
                    }.padding(32).frame(maxWidth: 1200)
                } else { ContentUnavailableView("Find your next moment.", systemImage: "waveform", description: Text("Import music in your library, then choose a track." )).frame(minHeight: geometry.size.height - 50) }
            }
            .background {
                if cinematic { RadialGradient(colors: [atmosphere.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: geometry.size.width * 0.7) }
            }
        }.sheet(isPresented: $queueShown) { QueueView() }
        .task(id: player.current?.id) {
            if let image = library.artwork(player.current), let color = image.sonorityAverageColor { atmosphere = Color(uiColor: color) }
            else { atmosphere = Palette.forest }
        }
    }
    private func cover(_ track: Track) -> some View {
        Artwork(image: library.artwork(track), radius: 28).aspectRatio(1, contentMode: .fit)
            .shadow(color: atmosphere.opacity(0.3), radius: 45, y: 20)
    }
    private func controls(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(track.title).font(.system(.largeTitle, design: .serif)).fixedSize(horizontal: false, vertical: true)
                    Text(track.artist).font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                Button { library.toggleFavorite(track.id) } label: { Image(systemName: library.track(track.id)?.favorite == true ? "heart.fill" : "heart").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Toggle favorite")
            }
            VStack(spacing: 8) {
                Slider(value: Binding(get: { dragging ? scrub : player.position }, set: { scrub = $0 }), in: 0...max(0.1, player.duration)) { editing in
                    if editing { scrub = player.position; dragging = true }
                    else { dragging = false; player.seek(scrub) }
                }.disabled(player.duration == 0).accessibilityLabel("Playback position").accessibilityValue(clockTime(player.position))
                HStack { Text(clockTime(dragging ? scrub : player.position)); Spacer(); Text("−" + clockTime(player.duration - (dragging ? scrub : player.position))) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 32) {
                Spacer(minLength: 0)
                Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Previous track")
                Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title).foregroundStyle(Palette.charcoal).frame(width: 76, height: 76).background(Palette.mint, in: Circle()) }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Next track")
                Spacer(minLength: 0)
            }
            HStack {
                Button { player.shuffle() } label: { Label("Shuffle queue", systemImage: "shuffle").frame(minHeight: 44) }.accessibilityLabel("Shuffle upcoming queue")
                Spacer()
                Button { player.cycleRepeat() } label: { Image(systemName: player.queue.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(player.queue.repeatMode == .off ? Color.secondary : Palette.mint).frame(width: 44, height: 44) }.accessibilityLabel("Repeat: \(player.queue.repeatMode.rawValue)")
            }
            Text("IMPORTED AUDIO · OFFLINE READY").font(.system(size: 9, weight: .semibold)).tracking(2.5).foregroundStyle(.secondary)
        }
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.ids.enumerated()), id: \.offset) { index, id in
                    HStack {
                        Image(systemName: index == player.queue.index ? "waveform" : "music.note").foregroundStyle(Palette.mint)
                        Button { player.playQueue(at: index) } label: {
                            VStack(alignment: .leading) { Text(library.track(id)?.title ?? "Unavailable track"); Text(library.track(id)?.artist ?? "").font(.caption).foregroundStyle(.secondary) }
                        }.buttonStyle(.plain)
                        Spacer()
                        if index > 0 { Button { player.moveQueue(from: index, to: index - 1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless).accessibilityLabel("Move up") }
                    }
                }.onDelete { indices in for index in indices.sorted(by: >) { player.removeQueue(index) } }
            }.navigationTitle("Your queue").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

import CoreImage
extension UIImage {
    var sonorityAverageColor: UIColor? {
        guard let input = CIImage(image: self), let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]), let output = filter.outputImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(output, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bytes[0]) / 255, green: CGFloat(bytes[1]) / 255, blue: CGFloat(bytes[2]) / 255, alpha: 1)
    }
}
