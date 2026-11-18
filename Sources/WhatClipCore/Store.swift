import Foundation
import SQLite3
import CryptoKit

public enum StoreError: Error, Equatable { case open(String), sql(String) }

private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Local clipboard history in SQLite. Large payloads (images, GIFs, rich text, file lists) are stored as private files next to the
/// database, named by their SHA-256, and referenced from the row. Thread-safe through one lock. Clipboard contents are never logged.
public final class ClipStore: @unchecked Sendable {
    var db: OpaquePointer?
    let lock = NSLock()
    private let now: @Sendable () -> Date
    private let blobDir: URL
    /// When set, new image and file payloads are encrypted on disk.
    public var cipher: PayloadCipher?
    /// Encrypt new payloads (existing ones stay readable as long as the cipher is set).
    public var encryptNew = false

    /// `path` nil or ":memory:" keeps everything in memory (tests); payloads then go to a temporary folder.
    public init(path: String? = nil, now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.now = now
        let persistent = path != nil && path != ":memory:"
        blobDir = persistent ? URL(fileURLWithPath: path!).deletingLastPathComponent().appendingPathComponent("blobs")
                             : FileManager.default.temporaryDirectory.appendingPathComponent("whatclip-blobs-\(UUID().uuidString)")
        if sqlite3_open(path ?? ":memory:", &db) != SQLITE_OK { throw StoreError.open(String(cString: sqlite3_errmsg(db))) }
        try exec("PRAGMA journal_mode=WAL; PRAGMA user_version=2;")
        try exec("""
        CREATE TABLE IF NOT EXISTS items(
          id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, text TEXT NOT NULL, fingerprint TEXT NOT NULL UNIQUE,
          source TEXT, created REAL NOT NULL, last_used REAL NOT NULL, use_count INTEGER NOT NULL DEFAULT 1,
          pinned INTEGER NOT NULL DEFAULT 0, expires REAL, secrets TEXT NOT NULL DEFAULT '',
          payload_type TEXT, payload_file TEXT);
        CREATE INDEX IF NOT EXISTS items_last_used ON items(last_used DESC);
        """)
        // Databases from version 1 lack the payload columns.
        let cols = try columnNames()
        if !cols.contains("payload_type") { try exec("ALTER TABLE items ADD COLUMN payload_type TEXT") }
        if !cols.contains("payload_file") { try exec("ALTER TABLE items ADD COLUMN payload_file TEXT") }
        if !cols.contains("ocr") { try exec("ALTER TABLE items ADD COLUMN ocr TEXT NOT NULL DEFAULT ''") }
        if !cols.contains("favorite") { try exec("ALTER TABLE items ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0") }
        if !cols.contains("tags") { try exec("ALTER TABLE items ADD COLUMN tags TEXT NOT NULL DEFAULT ''") }
        try exec("""
        CREATE TABLE IF NOT EXISTS snippets(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, folder TEXT NOT NULL DEFAULT '', favorite INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS boards(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, color TEXT NOT NULL DEFAULT 'blue');
        CREATE TABLE IF NOT EXISTS board_items(board_id INTEGER NOT NULL, item_id INTEGER NOT NULL, PRIMARY KEY(board_id, item_id));
        """)
        if !(try columnNames("snippets")).contains("tags") { try exec("ALTER TABLE snippets ADD COLUMN tags TEXT NOT NULL DEFAULT ''") }
        if persistent { Self.restrict(path!); try? FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }
    deinit { sqlite3_close(db) }

    /// The database, its write-ahead log and shared-memory file are readable only by the user.
    public static func restrict(_ path: String) {
        for p in [path, path + "-wal", path + "-shm"] where FileManager.default.fileExists(atPath: p) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p)
        }
    }

    private func columnNames(_ table: String = "items") throws -> [String] {
        var out: [String] = []
        try run("PRAGMA table_info(\(table))") { out.append(String(cString: sqlite3_column_text($0, 1))) }
        return out
    }
    func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
    }
    func run(_ sql: String, _ binds: [Bind] = [], row: ((OpaquePointer) -> Void)? = nil) throws {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(st) }
        for (i, b) in binds.enumerated() {
            let n = Int32(i + 1)
            switch b {
            case .text(let s): sqlite3_bind_text(st, n, s, -1, TRANSIENT)
            case .int(let v): sqlite3_bind_int64(st, n, v)
            case .real(let v): sqlite3_bind_double(st, n, v)
            case .null: sqlite3_bind_null(st, n)
            }
        }
        while true {
            let rc = sqlite3_step(st)
            if rc == SQLITE_ROW { row?(st) } else if rc == SQLITE_DONE { break } else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
        }
    }
    enum Bind { case text(String), int(Int64), real(Double), null }

    func itemFromRow(_ st: OpaquePointer) -> ClipItem { item(st) }

    /// Text and OCR values stored as "enc:" + base64 are decrypted here when a cipher is available.
    func revealed(_ raw: String) -> String {
        guard raw.hasPrefix("enc:") else { return raw }
        guard let c = cipher, let data = Data(base64Encoded: String(raw.dropFirst(4))), let plain = c.open(data) else { return "[locked: key not available]" }
        return String(decoding: plain, as: UTF8.self)
    }
    /// Stored form of a text value: plain, or sealed when text encryption is on.
    func stored(_ value: String) throws -> String {
        guard encryptNew, let c = cipher else { return value }
        return "enc:" + (try c.seal(Data(value.utf8))).base64EncodedString()
    }

    func item(_ st: OpaquePointer) -> ClipItem {
        func s(_ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
        func opt(_ i: Int32) -> String? { sqlite3_column_type(st, i) == SQLITE_NULL ? nil : s(i) }
        let exp: Date? = sqlite3_column_type(st, 9) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, 9))
        return ClipItem(id: sqlite3_column_int64(st, 0), kind: ClipKind(rawValue: s(1)) ?? .text, text: revealed(s(2)), fingerprint: s(3),
                        sourceBundleID: opt(4),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 5)), lastUsedAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 6)),
                        useCount: Int(sqlite3_column_int64(st, 7)), pinned: sqlite3_column_int64(st, 8) != 0, expiresAt: exp,
                        secretKinds: s(10).split(separator: ",").compactMap { SecretKind(rawValue: String($0)) },
                        payloadType: opt(11), payloadFile: opt(12), favorite: sqlite3_column_int64(st, 13) != 0)
    }
    private static let columns = "id,kind,text,fingerprint,source,created,last_used,use_count,pinned,expires,secrets,payload_type,payload_file,favorite"

    // MARK: payload files

    /// The private file that holds a payload, or nil when the item has none or the file is missing.
    public func payloadURL(for item: ClipItem) -> URL? {
        guard let name = item.payloadFile else { return nil }
        for candidate in [name, name + ".enc"] {
            let u = blobDir.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// The payload bytes, decrypted when needed. Nil when there is none or it cannot be opened (wrong key).
    public func payloadData(for item: ClipItem) -> Data? {
        guard let url = payloadURL(for: item), let raw = try? Data(contentsOf: url) else { return nil }
        if url.pathExtension == "enc" { return cipher?.open(raw) }
        return raw
    }

    private func writeBlob(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let encrypt = cipher != nil && encryptNew
        let stored = encrypt ? name + ".enc" : name
        let url = blobDir.appendingPathComponent(stored)
        if !FileManager.default.fileExists(atPath: url.path) {
            let bytes = encrypt ? try cipher!.seal(data) : data
            try bytes.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return stored
    }

    /// Deletes payload files that no item refers to any more.
    private func pruneBlobs() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: blobDir.path) else { return }
        var used = Set<String>()
        try? run("SELECT payload_file FROM items WHERE payload_file IS NOT NULL") { used.insert(String(cString: sqlite3_column_text($0, 0))) }
        for f in files where !used.contains(f) && !used.contains(f.replacingOccurrences(of: ".enc", with: "")) {
            try? FileManager.default.removeItem(at: blobDir.appendingPathComponent(f))
        }
    }

    // MARK: writing

    /// Adds a text item. The same text again moves the existing item to the top (use count +1) instead of adding a duplicate.
    @discardableResult
    public func add(text: String, sourceBundleID: String? = nil, expiresIn: TimeInterval? = nil, secretKinds: [SecretKind] = []) throws -> ClipItem {
        try addItem(kind: classify(text), text: text, fingerprint: fingerprint(of: text), sourceBundleID: sourceBundleID,
                    expiresIn: expiresIn, secretKinds: secretKinds, payloadType: nil, payload: nil)
    }

    /// Adds an item of a given kind without a payload file (used for copied file lists, whose text holds the paths).
    @discardableResult
    public func add(kind: ClipKind, text: String, sourceBundleID: String? = nil) throws -> ClipItem {
        try addItem(kind: kind, text: text, fingerprint: fingerprint(of: "\(kind.rawValue):\(text)"), sourceBundleID: sourceBundleID,
                    expiresIn: nil, secretKinds: [], payloadType: nil, payload: nil)
    }

    /// Adds an image, GIF, rich text or other binary payload. `label` is what the list shows (for example "Image 1200 × 800").
    /// Identical payloads are stored once.
    @discardableResult
    public func add(kind: ClipKind, label: String, payload: Data, payloadType: String, sourceBundleID: String? = nil, ocr: String = "") throws -> ClipItem {
        lock.lock(); defer { lock.unlock() }
        let fp = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let item = try addItemLocked(kind: kind, text: label, fingerprint: fp, sourceBundleID: sourceBundleID, expiresIn: nil,
                                     secretKinds: [], payloadType: payloadType, payload: payload)
        if !ocr.isEmpty { try run("UPDATE items SET ocr=? WHERE id=?", [.text(try stored(ocr)), .int(item.id)]) }
        return item
    }
    /// Saves the text read from an image later, in the background, so capturing never waits for recognition.
    public func setOCR(_ id: Int64, _ text: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard !text.isEmpty else { return }
        try run("UPDATE items SET ocr=? WHERE id=?", [.text(try stored(text)), .int(id)])
    }

    /// The text recognised in an image (empty when none was found).
    public func ocrText(for id: Int64) -> String {
        lock.lock(); defer { lock.unlock() }
        return ocrUnlocked(id)
    }
    /// Same as ocrText; the caller must already hold the lock.
    func ocrUnlocked(_ id: Int64) -> String {
        var out = ""
        try? run("SELECT ocr FROM items WHERE id=?", [.int(id)]) { out = self.revealed(String(cString: sqlite3_column_text($0, 0))) }
        return out
    }
    /// Same as tags(for:); the caller must already hold the lock.
    func tagsUnlocked(_ id: Int64) -> [String] {
        var out = ""
        try? run("SELECT tags FROM items WHERE id=?", [.int(id)]) { out = String(cString: sqlite3_column_text($0, 0)) }
        return out.split(separator: ",").map(String.init)
    }

    private func addItem(kind: ClipKind, text: String, fingerprint fp: String, sourceBundleID: String?, expiresIn: TimeInterval?,
                         secretKinds: [SecretKind], payloadType: String?, payload: Data?) throws -> ClipItem {
        lock.lock(); defer { lock.unlock() }
        return try addItemLocked(kind: kind, text: text, fingerprint: fp, sourceBundleID: sourceBundleID, expiresIn: expiresIn,
                                 secretKinds: secretKinds, payloadType: payloadType, payload: payload)
    }

    private func addItemLocked(kind: ClipKind, text: String, fingerprint fp: String, sourceBundleID: String?, expiresIn: TimeInterval?,
                               secretKinds: [SecretKind], payloadType: String?, payload: Data?) throws -> ClipItem {
        let t = now().timeIntervalSince1970
        let exp: Bind = expiresIn.map { .real(t + $0) } ?? .null
        let file: Bind = try payload.map { .text(try writeBlob($0)) } ?? .null
        let storedText = try stored(text)
        try run("""
        INSERT INTO items(kind,text,fingerprint,source,created,last_used,expires,secrets,payload_type,payload_file) VALUES(?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(fingerprint) DO UPDATE SET last_used=excluded.last_used, use_count=use_count+1, source=COALESCE(excluded.source, source),
          expires=CASE WHEN pinned=1 THEN NULL ELSE excluded.expires END
        """, [.text(kind.rawValue), .text(storedText), .text(fp), sourceBundleID.map { .text($0) } ?? .null, .real(t), .real(t), exp,
              .text(secretKinds.map(\.rawValue).joined(separator: ",")), payloadType.map { .text($0) } ?? .null, file])
        var out: ClipItem?
        try run("SELECT \(Self.columns) FROM items WHERE fingerprint=?", [.text(fp)]) { out = self.item($0) }
        return out!
    }

    /// Tags are short lowercase words, kept comma-separated. Empty entries are dropped.
    public func setTags(_ id: Int64, _ tags: [String]) throws {
        lock.lock(); defer { lock.unlock() }
        let clean = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: "") }.filter { !$0.isEmpty })).sorted()
        try run("UPDATE items SET tags=? WHERE id=?", [.text(clean.joined(separator: ",")), .int(id)])
    }
    public func tags(for id: Int64) -> [String] {
        lock.lock(); defer { lock.unlock() }
        var out = ""
        try? run("SELECT tags FROM items WHERE id=?", [.int(id)]) { out = self.revealed(String(cString: sqlite3_column_text($0, 0))) }
        return out.split(separator: ",").map(String.init)
    }
    /// Edits the text of a text item. Duplicates are refused (another item already has this text), so nothing is merged silently.
    public func updateText(_ id: Int64, to newText: String) throws {
        lock.lock(); defer { lock.unlock() }
        let fp = fingerprint(of: newText)
        var taken: Int64?
        try run("SELECT id FROM items WHERE fingerprint=? AND id<>?", [.text(fp), .int(id)]) { taken = sqlite3_column_int64($0, 0) }
        if taken != nil { throw StoreError.sql("duplicate") }
        try run("UPDATE items SET text=?, fingerprint=?, kind=? WHERE id=?",
                [.text(try stored(newText)), .text(fp), .text(classify(newText).rawValue), .int(id)])
    }

    public func setFavorite(_ id: Int64, _ on: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        try run("UPDATE items SET favorite=? WHERE id=?", [.int(on ? 1 : 0), .int(id)])
    }
    /// Source apps seen in history, most recent first (for the app filter).
    public func sourceApps() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        var out: [String] = []
        try run("SELECT source FROM items WHERE source IS NOT NULL GROUP BY source ORDER BY MAX(last_used) DESC LIMIT 40") { out.append(String(cString: sqlite3_column_text($0, 0))) }
        return out
    }
    /// Deletes several items at once (multi-select in the history window).
    public func delete(_ ids: [Int64]) throws {
        lock.lock(); defer { lock.unlock() }
        for id in ids { try run("DELETE FROM items WHERE id=?", [.int(id)]) }
        pruneBlobs()
    }

    public func setPinned(_ id: Int64, _ pinned: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        // A pinned item never expires.
        try run("UPDATE items SET pinned=?, expires=CASE WHEN ?=1 THEN NULL ELSE expires END WHERE id=?", [.int(pinned ? 1 : 0), .int(pinned ? 1 : 0), .int(id)])
    }
    public func delete(_ id: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        try run("DELETE FROM items WHERE id=?", [.int(id)]); pruneBlobs()
    }
    public func clear(keepPinned: Bool = true) throws {
        lock.lock(); defer { lock.unlock() }
        try run(keepPinned ? "DELETE FROM items WHERE pinned=0 AND favorite=0" : "DELETE FROM items"); pruneBlobs()
    }

    /// Removes expired secrets, then old items past `maxAgeDays`, then the oldest beyond `maxItems`. Pinned items are never removed here.
    @discardableResult
    public func enforceRetention(maxItems: Int, maxAgeDays: Int?) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let t = now().timeIntervalSince1970
        func count() throws -> Int { var n = 0; try run("SELECT COUNT(*) FROM items") { n = Int(sqlite3_column_int64($0, 0)) }; return n }
        let before = try count()
        try run("DELETE FROM items WHERE pinned=0 AND expires IS NOT NULL AND expires<=?", [.real(t)])
        if let days = maxAgeDays { try run("DELETE FROM items WHERE pinned=0 AND favorite=0 AND last_used<?", [.real(t - Double(days) * 86_400)]) }
        try run("DELETE FROM items WHERE pinned=0 AND favorite=0 AND id NOT IN (SELECT id FROM items WHERE pinned=0 AND favorite=0 ORDER BY last_used DESC, id DESC LIMIT ?)", [.int(Int64(max(0, maxItems)))])
        let removed = before - (try count())
        if removed > 0 { pruneBlobs() }
        return removed
    }

    // MARK: reading

    /// Pinned first, then newest. `query` matches text case-insensitively (every word must appear).
    /// Filters for the picker and the history window. All optional; combine freely.
    public struct Filter: Sendable {
        public var since: Date?
        public var source: String?
        public var favoritesOnly = false
        public var tag: String?
        public var hasText = false       // images with text read by OCR
        public init(since: Date? = nil, source: String? = nil, favoritesOnly: Bool = false, tag: String? = nil, hasText: Bool = false) {
            self.since = since; self.source = source; self.favoritesOnly = favoritesOnly; self.tag = tag; self.hasText = hasText
        }
    }

    /// The most recent copy by time, whether or not it is pinned. (`list` puts pinned items first, so it cannot answer this.)
    public func newestCopy() throws -> ClipItem? {
        lock.lock(); defer { lock.unlock() }
        var out: ClipItem?
        try run("SELECT \(Self.columns) FROM items WHERE (expires IS NULL OR expires>?) ORDER BY last_used DESC, id DESC LIMIT 1",
                [.real(now().timeIntervalSince1970)]) { out = self.item($0) }
        return out
    }

    public func list(query: String = "", limit: Int = 200, filter: Filter = Filter()) throws -> [ClipItem] {
        lock.lock(); defer { lock.unlock() }
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        // Encrypted text cannot be matched in SQL: with a cipher, fetch the rows and match the decrypted text here.
        if cipher != nil, !words.isEmpty {
            var rows: [ClipItem] = []
            try run("SELECT \(Self.columns) FROM items WHERE (expires IS NULL OR expires>?) ORDER BY pinned DESC, last_used DESC, id DESC LIMIT 5000",
                    [.real(now().timeIntervalSince1970)]) { rows.append(self.item($0)) }
            return rows.filter { r in
                (filter.since.map { r.lastUsedAt >= $0 } ?? true) && (filter.source.map { r.sourceBundleID == $0 } ?? true)
                && (!filter.favoritesOnly || r.favorite) && (filter.tag.map { tagsUnlocked(r.id).contains($0.lowercased()) } ?? true)
                && words.allSatisfy { w in r.text.localizedCaseInsensitiveContains(w) || ocrUnlocked(r.id).localizedCaseInsensitiveContains(w) }
            }.prefix(limit).map { $0 }
        }
        var sql = "SELECT \(Self.columns) FROM items WHERE (expires IS NULL OR expires>?)"
        var binds: [Bind] = [.real(now().timeIntervalSince1970)]
        if let since = filter.since { sql += " AND last_used>=?"; binds.append(.real(since.timeIntervalSince1970)) }
        if let source = filter.source { sql += " AND source=?"; binds.append(.text(source)) }
        if filter.favoritesOnly { sql += " AND favorite=1" }
        if let tag = filter.tag { sql += " AND (','||tags||',') LIKE ?"; binds.append(.text("%," + tag.lowercased() + ",%")) }
        if filter.hasText { sql += " AND ocr<>''" }
        for w in words {
            sql += " AND (text LIKE ? ESCAPE '\\' OR ocr LIKE ? ESCAPE '\\')"
            let like = Bind.text("%" + w.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%")
            binds.append(like); binds.append(like)
        }
        sql += " ORDER BY pinned DESC, last_used DESC, id DESC LIMIT ?"
        binds.append(.int(Int64(limit)))
        var out: [ClipItem] = []
        try run(sql, binds) { out.append(self.item($0)) }
        return out
    }
    public func count() throws -> Int { lock.lock(); defer { lock.unlock() }; var n = 0; try run("SELECT COUNT(*) FROM items") { n = Int(sqlite3_column_int64($0, 0)) }; return n }
}
