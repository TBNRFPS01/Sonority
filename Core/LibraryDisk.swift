import Foundation

/// All mutations are serialized by the app's main-actor store. Atomic replacement keeps the previous file intact on failed writes.
public struct LibraryDisk: Sendable {
    public let root: URL
    public var libraryURL: URL { root.appendingPathComponent("library.json") }
    public init(root: URL) { self.root = root }
    public func prepare() throws {
        for folder in ["Audio", "Artwork", "Lyrics"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }
    public func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return LibrarySnapshot() }
        let data = try Data(contentsOf: libraryURL)
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        guard snapshot.version == 1 else { throw CocoaError(.fileReadUnknown) }
        return snapshot
    }
    public func save(_ snapshot: LibrarySnapshot) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: libraryURL, options: .atomic)
    }
    public func audio(_ track: Track) -> URL { root.appendingPathComponent("Audio").appendingPathComponent(track.filename) }
    public func lyrics(_ id: UUID) -> URL { root.appendingPathComponent("Lyrics/\(id.uuidString).json") }
}
