import Foundation

/// Fuzzy matching: every character of the query appears in the text, in order, ignoring case.
/// Written for WhatClip after reading Maccy's search modes (MIT); the matching rule is ours.
public enum FuzzyMatch {
    public static func matches(_ query: String, in text: String) -> Bool {
        let q = query.lowercased().filter { !$0.isWhitespace }
        guard !q.isEmpty else { return true }
        var it = q.makeIterator()
        var want = it.next()
        for c in text.lowercased() {
            if c == want { want = it.next(); if want == nil { return true } }
        }
        return false
    }
}

/// How pasted text is changed on the way out. Mirrors the choices in Kelsiito's SmartPaste (MIT).
public enum PasteFormat: String, CaseIterable, Sendable {
    case original, plainText, markdown, prettyJSON, markdownLink

    public var title: String {
        switch self {
        case .original: "Original"; case .plainText: "Plain text"; case .markdown: "Clean Markdown"
        case .prettyJSON: "Format JSON"; case .markdownLink: "Markdown link"
        }
    }

    /// Returns the text to paste. When the format does not apply, the original text is returned unchanged.
    public func apply(_ text: String) -> String {
        switch self {
        case .original: return text
        case .plainText: return text.replacingOccurrences(of: "\r", with: "")
        case .markdown:
            return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        case .prettyJSON: return TextTool.jsonFormat.apply(text) ?? text
        case .markdownLink:
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard classify(t) == .url else { return text }
            return "[\(t)](\(t))"
        }
    }
}

/// Patterns that decide what is never recorded (Maccy has the same idea). Invalid patterns are ignored, never crash.
public struct IgnorePatterns: Sendable {
    public let regexps: [NSRegularExpression]
    public init(_ patterns: [String]) {
        regexps = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }
    public func ignores(_ text: String) -> Bool {
        let whole = NSRange(text.startIndex..., in: text)
        return regexps.contains { $0.firstMatch(in: text, range: whole) != nil }
    }
}
