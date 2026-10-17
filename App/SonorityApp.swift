import SwiftUI

@main
struct SonorityApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var player: AudioPlayer
    @StateObject private var spotify = SpotifyClient()
    init() {
        let store = LibraryStore()
        _library = StateObject(wrappedValue: store)
        let audio = AudioPlayer(store: store); audio.restoreProfile()
        _player = StateObject(wrappedValue: audio)
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(library).environmentObject(player).environmentObject(spotify)
                .preferredColorScheme(.dark).tint(Palette.mint)
        }
    }
}
