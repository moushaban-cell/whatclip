import Foundation
import SQLite3

public struct Snippet: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var title: String
    public var body: String
    public var folder: String
    public var favorite: Bool
    public var tags: String = ""
}

public struct Board: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var name: String
    public var colorName: String
}

/// The colours a board can use. Stored by name.
public enum BoardColor: String, CaseIterable, Sendable {
    case blue, green, amber, red, purple, gray
    public var title: String { rawValue.capitalized }
}

/// Fill-in templates: `{{name}}` placeholders. Pure, unit-tested.
public enum Template {
    /// Every placeholder name in order of first appearance.
    public static func variables(in body: String) -> [String] {
        var out: [String] = []
        var rest = Substring(body)
        while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !name.contains("\n"), !out.contains(name) { out.append(name) }
            rest = rest[close.upperBound...]
        }
        return out
    }

    /// Replaces each placeholder with its value. Placeholders without a value are left as they are.
    public static func render(_ body: String, values: [String: String]) -> String {
        var out = ""
        var rest = Substring(body)
        while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
            out += rest[..<open.lowerBound]
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            out += values[name] ?? String(rest[open.lowerBound..<close.upperBound])
            rest = rest[close.upperBound...]
        }
        return out + rest
    }
}

extension ClipStore {
    // MARK: snippets
    public func addSnippet(title: String, body: String, folder: String = "") throws -> Snippet {
        lock.lock(); defer { lock.unlock() }
        let t = Date().timeIntervalSince1970
        try run("INSERT INTO snippets(title,body,folder,favorite,created) VALUES(?,?,?,0,?)", [.text(title), .text(body), .text(folder), .real(t)])
        var out: Snippet?
        try run("SELECT id,title,body,folder,favorite,tags FROM snippets WHERE id=last_insert_rowid()") { out = Self.snippet($0) }
        return out!
    }
    public func updateSnippet(_ s: Snippet) throws {
        lock.lock(); defer { lock.unlock() }
        try run("UPDATE snippets SET title=?, body=?, folder=?, favorite=?, tags=? WHERE id=?", [.text(s.title), .text(s.body), .text(s.folder), .int(s.favorite ? 1 : 0), .text(s.tags), .int(s.id)])
    }
    public func deleteSnippet(_ id: Int64) throws { lock.lock(); defer { lock.unlock() }; try run("DELETE FROM snippets WHERE id=?", [.int(id)]) }
    public func snippets(query: String = "") throws -> [Snippet] {
        lock.lock(); defer { lock.unlock() }
        let like = "%" + query.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
        var out: [Snippet] = []
        try run("SELECT id,title,body,folder,favorite,tags FROM snippets WHERE title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\' OR tags LIKE ? ESCAPE '\\' ORDER BY favorite DESC, title",
                [.text(like), .text(like), .text(like)]) { out.append(Self.snippet($0)) }
        return out
    }
    private static func snippet(_ st: OpaquePointer) -> Snippet {
        func s(_ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
        return Snippet(id: sqlite3_column_int64(st, 0), title: s(1), body: s(2), folder: s(3), favorite: sqlite3_column_int64(st, 4) != 0, tags: s(5))
    }

    // MARK: boards
    public func addBoard(name: String, color: String = "blue") throws -> Board {
        lock.lock(); defer { lock.unlock() }
        try run("INSERT INTO boards(name,color) VALUES(?,?)", [.text(name), .text(color)])
        var out: Board?
        try run("SELECT id,name,color FROM boards WHERE id=last_insert_rowid()") { out = Board(id: sqlite3_column_int64($0, 0), name: String(cString: sqlite3_column_text($0, 1)), colorName: String(cString: sqlite3_column_text($0, 2))) }
        return out!
    }
    /// Sets a board's name and colour.
    public func updateBoard(_ id: Int64, name: String, color: BoardColor) throws {
        lock.lock(); defer { lock.unlock() }
        try run("UPDATE boards SET name=?, color=? WHERE id=?", [.text(name), .text(color.rawValue), .int(id)])
    }
    public func boards() throws -> [Board] {
        lock.lock(); defer { lock.unlock() }
        var out: [Board] = []
        try run("SELECT id,name,color FROM boards ORDER BY name") { out.append(Board(id: sqlite3_column_int64($0, 0), name: String(cString: sqlite3_column_text($0, 1)), colorName: String(cString: sqlite3_column_text($0, 2)))) }
        return out
    }
    public func deleteBoard(_ id: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        try run("DELETE FROM board_items WHERE board_id=?", [.int(id)]); try run("DELETE FROM boards WHERE id=?", [.int(id)])
    }
    /// Puts a history item on a board. The item stays in history too.
    public func addToBoard(item: Int64, board: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        try run("INSERT OR IGNORE INTO board_items(board_id,item_id) VALUES(?,?)", [.int(board), .int(item)])
    }
    public func removeFromBoard(item: Int64, board: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        try run("DELETE FROM board_items WHERE board_id=? AND item_id=?", [.int(board), .int(item)])
    }
    /// Items on a board, newest first. Items deleted from history drop off the board.
    public func items(onBoard board: Int64) throws -> [ClipItem] {
        lock.lock(); defer { lock.unlock() }
        var out: [ClipItem] = []
        try run("SELECT i.id,i.kind,i.text,i.fingerprint,i.source,i.created,i.last_used,i.use_count,i.pinned,i.expires,i.secrets,i.payload_type,i.payload_file FROM items i JOIN board_items b ON b.item_id=i.id WHERE b.board_id=? ORDER BY i.last_used DESC",
            [.int(board)]) { out.append(self.itemFromRow($0)) }
        return out
    }
}
