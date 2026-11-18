import Foundation

/// Export and import of history as JSON. Text, kinds, dates, pins, favourites and tags travel; image and file payloads do not
/// (they are large and are kept on the Mac that made them). Exports are written privately (mode 0600).
public enum Transfer {
    public struct Record: Codable, Equatable {
        public var kind: String
        public var text: String
        public var source: String?
        public var created: Date
        public var pinned: Bool
        public var favorite: Bool
        public var tags: [String]
    }
    public struct File: Codable, Equatable {
        public var format: String = "whatclip-history"
        public var version: Int = 1
        public var exportedAt: Date
        public var items: [Record]
    }

    public static func export(_ store: ClipStore) throws -> Data {
        let items = try store.list(limit: 100_000).filter { $0.payloadFile == nil && $0.kind != .image && $0.kind != .gif }
        let file = File(exportedAt: Date(), items: items.map {
            Record(kind: $0.kind.rawValue, text: $0.text, source: $0.sourceBundleID, created: $0.createdAt,
                   pinned: $0.pinned, favorite: $0.favorite, tags: store.tags(for: $0.id))
        })
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(file)
    }

    /// Imports records; returns how many were added. Unknown or malformed files throw; duplicates are merged by the store.
    @discardableResult
    public static func importData(_ data: Data, into store: ClipStore) throws -> Int {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let file = try dec.decode(File.self, from: data)
        guard file.format == "whatclip-history", file.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        var added = 0
        for r in file.items where !r.text.isEmpty && r.text.count <= 1_000_000 {
            let kind = ClipKind(rawValue: r.kind) ?? .text
            guard kind == .text || kind == .url || kind == .richText || kind == .file else { continue }
            let item = try store.add(kind: kind == .url ? .url : (kind == .file ? .file : .text), text: r.text, sourceBundleID: r.source)
            if r.pinned { try store.setPinned(item.id, true) }
            if r.favorite { try store.setFavorite(item.id, true) }
            if !r.tags.isEmpty { try store.setTags(item.id, r.tags) }
            added += 1
        }
        return added
    }
}
