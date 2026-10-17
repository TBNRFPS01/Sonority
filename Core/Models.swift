import Foundation

public struct Track: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var album: String
    public var filename: String
    public var artworkFilename: String?
    public var duration: Double
    public var favorite: Bool
    public var importedAt: Date
    public var embeddedLyrics: String?
    public init(id: UUID = UUID(), title: String, artist: String = "Unknown artist", album: String = "Singles", filename: String, artworkFilename: String? = nil, duration: Double = 0, favorite: Bool = false, importedAt: Date = Date(), embeddedLyrics: String? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.album = album
        self.filename = filename; self.artworkFilename = artworkFilename; self.duration = duration
        self.favorite = favorite; self.importedAt = importedAt; self.embeddedLyrics = embeddedLyrics
    }
}

public struct Playlist: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var trackIDs: [UUID] = []
    public init(name: String) { self.name = name }
}

public struct Listen: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var trackID: UUID
    public var date: Date
    public var seconds: Double
    public init(trackID: UUID, date: Date = Date(), seconds: Double) {
        self.trackID = trackID; self.date = date; self.seconds = seconds
    }
}

public struct SoundProfile: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var gains: [Float]
    public var bass: Float
    public var preamp: Float
    public init(name: String, gains: [Float] = [0, 0, 0, 0, 0], bass: Float = 0, preamp: Float = -6) {
        self.name = name; self.gains = gains; self.bass = bass; self.preamp = preamp
    }
}

public struct LibrarySnapshot: Codable, Sendable {
    public var version = 1
    public var tracks: [Track] = []
    public var playlists: [Playlist] = []
    public var history: [Listen] = []
    public var profiles: [SoundProfile] = []
    public init() {}
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable { case off, all, one }

public struct PlaybackQueue: Codable, Equatable, Sendable {
    public private(set) var ids: [UUID] = []
    public private(set) var index: Int = 0
    public var repeatMode: RepeatMode = .off
    public var current: UUID? { ids.indices.contains(index) ? ids[index] : nil }
    public init() {}
    public mutating func replace(_ values: [UUID], startingAt id: UUID) {
        ids = values; index = values.firstIndex(of: id) ?? 0
    }
    public mutating func append(_ id: UUID) { ids.append(id) }
    public mutating func select(at offset: Int) -> UUID? {
        guard ids.indices.contains(offset) else { return nil }
        index = offset; return current
    }
    public mutating func next(automatic: Bool = false) -> UUID? {
        guard !ids.isEmpty else { return nil }
        if automatic && repeatMode == .one { return current }
        if index + 1 < ids.count { index += 1; return current }
        if repeatMode == .all { index = 0; return current }
        return nil
    }
    public mutating func previous() -> UUID? { index = max(0, index - 1); return current }
    public mutating func remove(at offset: Int) {
        guard ids.indices.contains(offset) else { return }
        ids.remove(at: offset)
        if offset < index { index -= 1 }
        index = min(index, max(0, ids.count - 1))
    }
    public mutating func move(from: Int, to: Int) {
        guard ids.indices.contains(from), ids.indices.contains(to) else { return }
        let activeIndex = index
        let item = ids.remove(at: from); ids.insert(item, at: to)
        if activeIndex == from { index = to }
        else if from < activeIndex && to >= activeIndex { index -= 1 }
        else if from > activeIndex && to <= activeIndex { index += 1 }
    }
    public mutating func shuffleUpcoming() {
        guard index + 1 < ids.count else { return }
        let tail = ids[(index + 1)...].shuffled()
        ids.replaceSubrange((index + 1)..<ids.count, with: tail)
    }
}
