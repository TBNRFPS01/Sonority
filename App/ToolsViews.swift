import SwiftUI
import SonorityCore

struct SoundLabView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var saving = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SectionHeading(eyebrow: "Sound Lab", title: "Make it feel like you.", subtitle: "Real processing for Sonority’s local audio. Spotify plays in its own app.")
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Label("Output level", systemImage: "waveform"); Spacer(); Text(player.isPlaying ? "LIVE RMS" : "IDLE").font(.caption.monospaced()).foregroundStyle(Palette.mint) }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) { Capsule().fill(.white.opacity(0.06)); Capsule().fill(LinearGradient(colors: [Palette.forest, Palette.mint], startPoint: .leading, endPoint: .trailing)).frame(width: max(0, proxy.size.width * CGFloat(player.level))) }
                    }.frame(height: 26).animation(reduceMotion ? nil : .linear(duration: 0.1), value: player.level).accessibilityLabel("Output amplitude").accessibilityValue("\(Int(player.level * 100)) percent")
                    Text("Measured from the local audio mixer; this is an amplitude meter, not a simulated spectrum.").font(.caption).foregroundStyle(.secondary)
                }.panel()
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Equalizer").font(.title2.weight(.medium)); Spacer()
                        Menu("Profiles") {
                            Button("Reference") { player.profile = SoundProfile(name: "Reference") }
                            Button("Warm") { player.profile = SoundProfile(name: "Warm", gains: [2, 1, 0, -1, -2], bass: 1, preamp: -9) }
                            ForEach(library.library.profiles) { profile in Button(profile.name) { player.profile = profile } }
                        }
                    }
                    ForEach(0..<5) { index in
                        VStack(alignment: .leading) {
                            HStack { Text(["60 Hz", "230 Hz", "910 Hz", "3.6 kHz", "14 kHz"][index]); Spacer(); Text(String(format: "%+.1f dB", player.profile.gains[index])).monospacedDigit() }.font(.subheadline)
                            Slider(value: Binding(get: { Double(player.profile.gains[index]) }, set: { player.profile.gains[index] = Float($0) }), in: -12...12, step: 0.5).accessibilityLabel("Equalizer band \(index + 1)")
                        }
                    }
                    Text("Bass shelf · \(player.profile.bass, specifier: "%.1f") dB").font(.subheadline)
                    Slider(value: Binding(get: { Double(player.profile.bass) }, set: { player.profile.bass = Float($0) }), in: 0...6, step: 0.5).accessibilityLabel("Bass boost")
                    Text("Headroom · \(player.profile.preamp, specifier: "%.1f") dB").font(.subheadline)
                    Slider(value: Binding(get: { Double(player.profile.preamp) }, set: { player.profile.preamp = Float($0) }), in: -24...0, step: 0.5).accessibilityLabel("Preamp headroom")
                    Text("Boosts can clip. Reduce the preamp when raising EQ bands or bass.").font(.caption).foregroundStyle(.secondary)
                    Button("Save sound profile", systemImage: "plus") { saving = true }
                }.panel()
            }.padding(28).frame(maxWidth: 1000)
        }.alert("Save profile", isPresented: $saving) {
            TextField("Name", text: $name)
            Button("Save") { if !name.trimmingCharacters(in: .whitespaces).isEmpty { var profile = player.profile; profile.id = UUID(); profile.name = name; library.saveProfile(profile); name = "" } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct OutputView: View {
    @EnvironmentObject private var player: AudioPlayer
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SectionHeading(eyebrow: "AirPods & Output", title: "Connected to the moment.", subtitle: "Information reported by the current system audio session.")
                VStack(spacing: 22) {
                    Image(systemName: "airpodspro").font(.system(size: 76, weight: .ultraLight)).foregroundStyle(Palette.mint).accessibilityHidden(true)
                    Text(player.routeName.isEmpty ? "No active route" : player.routeName).font(.title2)
                    LabeledContent("Transport", value: player.routeType)
                    LabeledContent("Session sample rate", value: player.sampleRate > 0 ? "\(Int(player.sampleRate)) Hz" : "Not reported")
                    LabeledContent("Output channels", value: "\(player.outputChannels)")
                    LabeledContent("Spatial playback reported by port", value: player.spatialAudioReported ? "Yes" : "No")
                    LabeledContent("Reported output latency", value: "\(Int(player.outputLatency * 1000)) ms")
                    HStack { Text("Choose audio output"); Spacer(); RoutePicker().frame(width: 44, height: 44) }
                    Button("Refresh route") { player.refreshRoute() }
                }.panel()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Managed by iPadOS").font(.headline)
                    Text("Noise cancellation, Transparency, Adaptive Audio, personalized Spatial Audio, and ear detection are controlled in system settings or Control Center. Sonority does not expose private controls.")
                    Text("AirPods and case battery levels are not supplied by the public audio route API. No battery estimate is shown. A route name alone does not verify an AirPods model.")
                    Text("The sample rate above describes the app’s audio session, not the Bluetooth codec or a lossless transport guarantee.")
                }.font(.subheadline).foregroundStyle(.secondary).panel()
            }.padding(28).frame(maxWidth: 1000)
        }
    }
}

struct ListeningView: View {
    @EnvironmentObject private var library: LibraryStore
    private var seconds: Double { library.library.history.reduce(0) { $0 + $1.seconds } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SectionHeading(eyebrow: "Your listening", title: "Time, well spent.", subtitle: "Private, on-device history from local playback.")
                HStack(alignment: .firstTextBaseline, spacing: 12) { Text(String(format: "%.1f", seconds / 3600)).font(.system(size: 64, weight: .light, design: .rounded)); Text("hours listened").foregroundStyle(.secondary) }.panel()
                let totals = Dictionary(grouping: library.library.history, by: \.trackID).mapValues { $0.reduce(0) { $0 + $1.seconds } }
                Text("Most played").font(.title2)
                ForEach(totals.keys.sorted { totals[$0, default: 0] > totals[$1, default: 0] }.prefix(10), id: \.self) { id in
                    HStack { Text(library.track(id)?.title ?? "Removed track"); Spacer(); Text("\(Int(totals[id, default: 0] / 60)) min").monospacedDigit().foregroundStyle(.secondary) }.padding(.vertical, 8)
                }
                Text("Recent listening").font(.title2)
                ForEach(library.library.history.reversed().prefix(40)) { listen in
                    HStack { VStack(alignment: .leading, spacing: 4) { Text(library.track(listen.trackID)?.title ?? "Removed track"); Text(listen.date, style: .date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(clockTime(listen.seconds)).font(.caption.monospacedDigit()) }
                }
                if library.library.history.isEmpty { ContentUnavailableView("Your story starts with a song.", systemImage: "chart.bar", description: Text("Listening time appears after local playback. Paused time and seeks are excluded.")) }
            }.padding(28).frame(maxWidth: 1000)
        }
    }
}

struct SettingsView: View {
    @AppStorage("cinematic") private var cinematic = true
    @AppStorage("cleanLyrics") private var clean = false
    var body: some View {
        Form {
            Section("Your space") { Toggle("Cinematic atmosphere", isOn: $cinematic); Toggle("Clean lyrics reading mode", isOn: $clean) }
            Section("Privacy") { Text("Local music, imported lyrics, history, and sound profiles stay in this app’s storage. There is no Sonority account or analytics service. Spotify credentials are stored in Keychain; its API is contacted only when you connect or load Spotify content.") }
            Section("Access") { Text("Sonority follows Dynamic Type and Reduce Motion. The app supports iPad portrait, landscape, and resizable multitasking windows.") }
            Section("Sonority · 1.0") { Text("Built around the music you own.").font(.system(.title3, design: .serif)) }
        }.scrollContentBackground(.hidden)
    }
}
