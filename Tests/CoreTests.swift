import XCTest
@testable import SonorityCore

final class CoreTests: XCTestCase {
    func testLRCFractionsOffsetsRepeatedTagsAndTranslation() {
        let doc = LRCParser.parse("[offset:-500]\n[00:01.5][00:03.125]Hello\n[00:01.5]Bonjour\n[99:99]bad")
        XCTAssertEqual(doc.lines.count, 2)
        XCTAssertEqual(doc.lines[0].time, 1, accuracy: 0.001)
        XCTAssertEqual(doc.lines[1].time, 2.625, accuracy: 0.001)
        XCTAssertEqual(doc.lines[0].translation, "Bonjour")
        XCTAssertNil(doc.activeIndex(at: 0))
        XCTAssertEqual(doc.activeIndex(at: 1), 0)
        XCTAssertEqual(doc.activeIndex(at: 900), 1)
    }
    func testPlainLyrics() {
        XCTAssertEqual(LRCParser.parse("A line\nAnother line").plainText, "A line\nAnother line")
    }
    func testTranslationMatchTolerance() {
        let doc = LRCParser.parse("[00:01]Hello").mergingTranslation(LRCParser.parse("[00:01.05]Hola"))
        XCTAssertEqual(doc.lines.first?.translation, "Hola")
    }
    func testQueueBoundariesAndRepeat() {
        let a = UUID(), b = UUID()
        var q = PlaybackQueue(); q.replace([a, b], startingAt: a)
        XCTAssertEqual(q.previous(), a)
        XCTAssertEqual(q.next(), b)
        XCTAssertNil(q.next())
        q.repeatMode = .all; XCTAssertEqual(q.next(), a)
        q.repeatMode = .one; XCTAssertEqual(q.next(automatic: true), a)
        XCTAssertEqual(q.next(), b)
        q.remove(at: 0); XCTAssertEqual(q.current, b)
        q.remove(at: 0); XCTAssertNil(q.current)
    }
    func testQueueMovePreservesCurrentOccurrence() {
        let a = UUID(), b = UUID(), c = UUID()
        var q = PlaybackQueue(); q.replace([a, b, a, c], startingAt: b)
        q.move(from: 1, to: 3)
        XCTAssertEqual(q.current, b)
        q.move(from: 0, to: 3)
        XCTAssertEqual(q.current, b)
    }
    func testZeroAndMalformedTimestampsAndUnicode() {
        let doc = LRCParser.parse("[ar:Artist]\n[00:00]夜\n[00:02.05]écho\n[00:80]invalid\nuntimed")
        XCTAssertEqual(doc.lines.map(\.text), ["夜", "écho"])
        XCTAssertEqual(doc.lines[1].time, 2.05, accuracy: 0.001)
        XCTAssertEqual(doc.activeIndex(at: 0), 0)
    }
    func testEmptyQueueAndInvalidSelection() {
        var queue = PlaybackQueue()
        XCTAssertNil(queue.current); XCTAssertNil(queue.next()); XCTAssertNil(queue.previous())
        queue.remove(at: -1); queue.move(from: 0, to: 1)
        XCTAssertNil(queue.select(at: 0))
    }
    func testDuplicateQueueOccurrenceSelectionAndDeletion() {
        let a = UUID(), b = UUID()
        var queue = PlaybackQueue(); queue.replace([a, b, a], startingAt: a)
        XCTAssertEqual(queue.select(at: 2), a)
        XCTAssertEqual(queue.index, 2)
        queue.remove(at: 0)
        XCTAssertEqual(queue.index, 1); XCTAssertEqual(queue.current, a)
    }
    func testQueueAndProfileSerialization() throws {
        let a = UUID(), b = UUID()
        var queue = PlaybackQueue(); queue.replace([a, b], startingAt: b); queue.repeatMode = .one
        let restored = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(restored, queue)
        let profile = SoundProfile(name: "Warm", gains: [2, 1, 0, -1, -2], bass: 1, preamp: -9)
        XCTAssertEqual(try JSONDecoder().decode(SoundProfile.self, from: JSONEncoder().encode(profile)), profile)
    }
    func testFutureLibraryVersionIsRejectedWithoutReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = LibraryDisk(root: root); try disk.prepare()
        var snapshot = LibrarySnapshot(); snapshot.version = 99
        try disk.save(snapshot)
        let before = try Data(contentsOf: disk.libraryURL)
        XCTAssertThrowsError(try disk.load())
        XCTAssertEqual(try Data(contentsOf: disk.libraryURL), before)
    }
    func testPersistenceRoundTripAndCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = LibraryDisk(root: root); try disk.prepare()
        var library = LibrarySnapshot()
        library.tracks = [Track(title: "Test", filename: "test.wav")]
        library.playlists = [Playlist(name: "Evening")]
        try disk.save(library)
        XCTAssertEqual(try disk.load().tracks, library.tracks)
        try Data("broken".utf8).write(to: disk.libraryURL)
        XCTAssertThrowsError(try disk.load())
    }
}
