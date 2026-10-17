import SwiftUI
import AVFoundation
import SonorityCore

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var library = LibrarySnapshot()
    @Published var message: String?
    @Published var importing = false
    @Published private(set) var recoveryRequired = false
    let disk: LibraryDisk
    private let artworkCache = NSCache<NSString, UIImage>()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        disk = LibraryDisk(root: base.appendingPathComponent("Sonority", isDirectory: true))
        do { try disk.prepare(); library = try disk.load(); library.profiles = library.profiles.filter { $0.gains.count == 5 } }
        catch { recoveryRequired = true; message = "The library could not be read. Your files are preserved. Restore library.json from a backup before importing more music. \(error.localizedDescription)" }
    }
    func save() {
        guard !recoveryRequired else { return }
        do { try disk.save(library) } catch { message = "Could not save the library: \(error.localizedDescription)" }
    }
    func importAudio(_ urls: [URL]) async {
        guard !recoveryRequired, !importing else { return }
        importing = true; defer { importing = false }
        var failures: [String] = []
        for source in urls {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let id = UUID()
            let filename = id.uuidString + "." + source.pathExtension.lowercased()
            let destination = disk.root.appendingPathComponent("Audio/\(filename)")
            var artworkURL: URL?
            do {
                // Copy into our sandbox so imported music survives provider revocation and works offline.
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.copyItem(at: source, to: destination)
                }.value
                let file = try AVAudioFile(forReading: destination)
                guard file.length > 0, file.processingFormat.sampleRate > 0 else { throw CocoaError(.fileReadCorruptFile) }
                let asset = AVURLAsset(url: destination)
                let metadata = (try? await asset.load(.commonMetadata)) ?? []
                func string(_ key: AVMetadataKey) async -> String? {
                    guard let item = metadata.first(where: { $0.commonKey == key }) else { return nil }
                    return try? await item.load(.stringValue)
                }
                var artwork: String?
                if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
                   let data = try? await item.load(.dataValue), let image = UIImage(data: data),
                   let jpeg = image.preparingThumbnail(of: CGSize(width: 900, height: 900))?.jpegData(compressionQuality: 0.85) {
                    artwork = id.uuidString + ".jpg"
                    let url = disk.root.appendingPathComponent("Artwork/\(artwork!)")
                    artworkURL = url; try jpeg.write(to: url, options: .atomic)
                }
                let title = await string(.commonKeyTitle) ?? source.deletingPathExtension().lastPathComponent
                let artist = await string(.commonKeyArtist) ?? "Unknown artist"
                let album = await string(.commonKeyAlbumName) ?? "Singles"
                let lyrics = try? await asset.load(.lyrics)
                library.tracks.append(Track(id: id, title: title, artist: artist, album: album, filename: filename,
                    artworkFilename: artwork, duration: Double(file.length) / file.processingFormat.sampleRate, embeddedLyrics: lyrics))
                save()
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if let artworkURL { try? FileManager.default.removeItem(at: artworkURL) }
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { message = failures.joined(separator: "\n") }
    }
    func track(_ id: UUID?) -> Track? { library.tracks.first { $0.id == id } }
    func artwork(_ track: Track?) -> UIImage? {
        guard let name = track?.artworkFilename else { return nil }
        if let cached = artworkCache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: disk.root.appendingPathComponent("Artwork/\(name)").path) else { return nil }
        artworkCache.countLimit = 40; artworkCache.setObject(image, forKey: name as NSString)
        return image
    }
    func toggleFavorite(_ id: UUID) {
        guard let index = library.tracks.firstIndex(where: { $0.id == id }) else { return }
        library.tracks[index].favorite.toggle(); save()
    }
    func createPlaylist(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        library.playlists.append(Playlist(name: trimmed)); save()
    }
    func add(_ track: UUID, to playlist: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlist }), !library.playlists[index].trackIDs.contains(track) else { return }
        library.playlists[index].trackIDs.append(track); save()
    }
    func removeFromPlaylist(_ track: UUID, playlist: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == playlist }) else { return }
        library.playlists[index].trackIDs.removeAll { $0 == track }; save()
    }
    func deletePlaylist(_ id: UUID) { library.playlists.removeAll { $0.id == id }; save() }
    func deleteTrack(_ id: UUID) {
        guard !recoveryRequired, let track = track(id) else { return }
        library.tracks.removeAll { $0.id == id }
        for index in library.playlists.indices { library.playlists[index].trackIDs.removeAll { $0 == id } }
        save()
        // If the save failed, keep the files to avoid dangling references on next launch.
        guard (try? disk.load().tracks.contains(where: { $0.id == id })) == false else { return }
        try? FileManager.default.removeItem(at: disk.audio(track))
        try? FileManager.default.removeItem(at: disk.lyrics(id))
        if let artwork = track.artworkFilename { try? FileManager.default.removeItem(at: disk.root.appendingPathComponent("Artwork/\(artwork)")) }
    }
    func record(_ id: UUID, seconds: Double) {
        guard seconds > 0 else { return }
        if let last = library.history.indices.last, library.history[last].trackID == id,
           Date().timeIntervalSince(library.history[last].date) < 300 {
            library.history[last].seconds += seconds
        } else { library.history.append(Listen(trackID: id, seconds: seconds)) }
        library.history = Array(library.history.suffix(10000)); save()
    }
    func saveProfile(_ profile: SoundProfile) { library.profiles.append(profile); save() }
    func lyrics(for track: Track) -> LyricsDocument {
        if let data = try? Data(contentsOf: disk.lyrics(track.id)), let doc = try? JSONDecoder().decode(LyricsDocument.self, from: data) { return doc }
        return LRCParser.parse(track.embeddedLyrics ?? "")
    }
    func importLyrics(_ url: URL, track: Track, translation: Bool) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let text = try String(contentsOf: url, encoding: .utf8)
            let incoming = LRCParser.parse(text)
            if translation && (incoming.lines.isEmpty || lyrics(for: track).lines.isEmpty) {
                message = "Translations need timestamped LRC files for both the original and translation."; return
            }
            let result = translation ? lyrics(for: track).mergingTranslation(incoming) : incoming
            try JSONEncoder().encode(result).write(to: disk.lyrics(track.id), options: .atomic)
            objectWillChange.send()
        } catch { message = "Lyrics import failed: \(error.localizedDescription)" }
    }
}
