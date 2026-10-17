import Foundation

public struct LyricLine: Identifiable, Codable, Equatable, Sendable {
    public var id: Int
    public var time: Double
    public var text: String
    public var translation: String?
}

public struct LyricsDocument: Codable, Equatable, Sendable {
    public var lines: [LyricLine]
    public var plainText: String?
    public init(lines: [LyricLine] = [], plainText: String? = nil) { self.lines = lines; self.plainText = plainText }
    public func activeIndex(at seconds: Double) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= seconds { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
    public func mergingTranslation(_ other: LyricsDocument) -> LyricsDocument {
        var result = self
        for index in result.lines.indices {
            if let match = other.lines.first(where: { abs($0.time - result.lines[index].time) < 0.08 }) {
                result.lines[index].translation = match.text
            }
        }
        return result
    }
}

public enum LRCParser {
    public static func parse(_ source: String) -> LyricsDocument {
        let pattern = #"\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let offsetRegex = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let ns = source as NSString
        var offset = 0.0
        if let match = offsetRegex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) {
            offset = (Double(ns.substring(with: match.range(at: 1))) ?? 0) / 1000
        }
        var entries: [(Double, String, Int)] = []
        for (order, raw) in source.components(separatedBy: .newlines).enumerated() {
            let value = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: value.length))
            guard let last = matches.last else { continue }
            let text = value.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(value.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(value.substring(with: match.range(at: 2))) ?? 0
                guard seconds < 60 else { continue }
                let fractionRange = match.range(at: 3)
                let fraction = fractionRange.location == NSNotFound ? 0 : (Double("0." + value.substring(with: fractionRange)) ?? 0)
                entries.append((max(0, minutes * 60 + seconds + fraction + offset), text, order))
            }
        }
        entries.sort { $0.0 == $1.0 ? $0.2 < $1.2 : $0.0 < $1.0 }
        var lines: [LyricLine] = []
        for entry in entries {
            if let last = lines.last, last.time == entry.0 {
                if !entry.1.isEmpty { lines[lines.count - 1].translation = entry.1 }
            } else {
                lines.append(LyricLine(id: lines.count, time: entry.0, text: entry.1))
            }
        }
        return LyricsDocument(lines: lines, plainText: lines.isEmpty ? source : nil)
    }
}
