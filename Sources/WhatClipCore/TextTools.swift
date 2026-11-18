import Foundation

/// Text transformations offered on a copied item. Pure functions, all unit-tested.
public enum TextTool: String, CaseIterable, Sendable {
    case upper, lower, titleCase, trimWhitespace, removeDuplicateLines, removeEmptyLines, sortLines
    case jsonFormat, jsonMinify, urlEncode, urlDecode, base64Encode, base64Decode, plainText, stats

    public var title: String {
        switch self {
        case .upper: "UPPERCASE"; case .lower: "lowercase"; case .titleCase: "Title Case"
        case .trimWhitespace: "Trim whitespace"; case .removeDuplicateLines: "Remove duplicate lines"
        case .removeEmptyLines: "Remove empty lines"; case .sortLines: "Sort lines"
        case .jsonFormat: "Format JSON"; case .jsonMinify: "Minify JSON"
        case .urlEncode: "URL encode"; case .urlDecode: "URL decode"
        case .base64Encode: "Base64 encode"; case .base64Decode: "Base64 decode"
        case .plainText: "Copy as plain text"; case .stats: "Count words and characters"
        }
    }

    /// Returns the transformed text, or nil when the tool does not apply (for example JSON on text that is not JSON).
    public func apply(_ s: String) -> String? {
        switch self {
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .titleCase: return s.capitalized
        case .trimWhitespace: return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeDuplicateLines:
            var seen = Set<String>(); var out: [String] = []
            for l in s.components(separatedBy: "\n") where seen.insert(l).inserted { out.append(l) }
            return out.joined(separator: "\n")
        case .removeEmptyLines:
            return s.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        case .sortLines: return s.components(separatedBy: "\n").sorted().joined(separator: "\n")
        case .jsonFormat: return Self.json(s, options: .prettyPrinted)
        case .jsonMinify: return Self.json(s, options: [])
        case .urlEncode: return s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))
        case .urlDecode: return s.removingPercentEncoding
        case .base64Encode: return Data(s.utf8).base64EncodedString()
        case .base64Decode: return Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { String(data: $0, encoding: .utf8) }
        case .plainText: return s
        case .stats:
            let words = s.split(whereSeparator: \.isWhitespace).count
            let lines = s.isEmpty ? 0 : s.components(separatedBy: "\n").count
            return "\(words) words, \(s.count) characters, \(lines) lines"
        }
    }

    private static func json(_ s: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: o, options: options.union(.fragmentsAllowed)) else { return nil }
        return String(data: out, encoding: .utf8)
    }
}

/// Things worth an action in a copied text: links, emails, phone numbers, dates, colours, file paths.
public enum SmartKind: String, Sendable, CaseIterable { case email, phone, date, hexColor, filePath }

public enum SmartRecognizer {
    private static let patterns: [(SmartKind, NSRegularExpression)] = [
        (.email, try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)),
        (.phone, try! NSRegularExpression(pattern: #"\+?\d[\d\s().-]{7,}\d"#)),
        (.date, try! NSRegularExpression(pattern: #"\b\d{4}-\d{2}-\d{2}\b"#)),
        (.hexColor, try! NSRegularExpression(pattern: #"#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b"#)),
        (.filePath, try! NSRegularExpression(pattern: #"(?<![\w:/])/(?:[\w.-]+/)*[\w.-]+"#)),
    ]

    /// Each kind found, with the matched text, in the order they appear in the text. Duplicates removed.
    public static func find(in text: String) -> [(kind: SmartKind, value: String)] {
        let whole = NSRange(text.startIndex..., in: text)
        var hits: [(Int, SmartKind, String)] = []
        for (kind, re) in patterns {
            for m in re.matches(in: text, range: whole) {
                guard let r = Range(m.range, in: text) else { continue }
                let v = String(text[r])
                if kind == .phone, v.filter(\.isNumber).count < 8 { continue }
                hits.append((m.range.location, kind, v))
            }
        }
        var seen = Set<String>(); var out: [(SmartKind, String)] = []
        for (_, k, v) in hits.sorted(by: { $0.0 < $1.0 }) where seen.insert("\(k.rawValue):\(v)").inserted { out.append((k, v)) }
        return out.map { (kind: $0.0, value: $0.1) }
    }
}
