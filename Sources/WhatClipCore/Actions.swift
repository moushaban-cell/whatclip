import Foundation

/// How several items are joined when they are pasted together (the stack's merge).
public enum Separator: String, CaseIterable, Sendable {
    case newline, comma, space, tab, none
    public var title: String {
        switch self {
        case .newline: "One per line"; case .comma: "Comma separated"; case .space: "Space separated"
        case .tab: "Tab separated"; case .none: "No separator"
        }
    }
    public var text: String {
        switch self {
        case .newline: "\n"; case .comma: ", "; case .space: " "; case .tab: "\t"; case .none: ""
        }
    }
}

public enum Merge {
    /// Joins the texts with the separator. Empty items are skipped so no double separators appear.
    public static func join(_ texts: [String], separator: Separator) -> String {
        texts.map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }.joined(separator: separator.text)
    }
}

/// A user-defined action: a shell command that receives the item's text on standard input.
/// Its output becomes a new text item. Actions only run when the person chooses them.
public struct UserAction: Sendable, Equatable, Codable {
    public var name: String
    public var command: String

    public init(name: String, command: String) { self.name = name; self.command = command }

    /// Reads one action per line in the form "Name | command". Lines without both parts are ignored.
    public static func parse(_ text: String) -> [UserAction] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return UserAction(name: String(parts[0]), command: String(parts[1]))
        }
    }

    public static func format(_ actions: [UserAction]) -> String {
        actions.map { "\($0.name) | \($0.command)" }.joined(separator: "\n")
    }
}
