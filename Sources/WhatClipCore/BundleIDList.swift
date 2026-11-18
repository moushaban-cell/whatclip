import Foundation

/// Parses the excluded-apps list typed in Settings: one bundle identifier per line, or separated by commas or spaces.
/// First draft from a local model; its character check was wrong (it rejected "." and "-"), so it was rewritten and tested.
public enum BundleIDList {
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")

    public static func parse(_ text: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for piece in text.split(whereSeparator: { $0 == "," || $0.isNewline || $0 == " " || $0 == "\t" }) {
            let id = String(piece)
            guard !id.isEmpty, id.count <= 255, id.allSatisfy(allowed.contains), !seen.contains(id) else { continue }
            seen.insert(id); out.append(id)
        }
        return out
    }

    /// One identifier per line, sorted, no trailing newline.
    public static func format(_ ids: [String]) -> String {
        Array(Set(ids)).sorted().joined(separator: "\n")
    }
}
