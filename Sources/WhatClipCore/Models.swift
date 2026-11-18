import Foundation
import CryptoKit

public enum ClipKind: String, Sendable, Codable, CaseIterable {
    case text, url, richText, image, gif, file
    public var symbol: String {
        switch self { case .text: "text.alignleft"; case .url: "link"; case .richText: "textformat"; case .image: "photo"; case .gif: "play.rectangle"; case .file: "doc" }
    }
}

public struct ClipItem: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var kind: ClipKind
    public var text: String
    public var fingerprint: String
    public var sourceBundleID: String?
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int
    public var pinned: Bool
    /// When set, the item is removed after this time (used for items that look like secrets).
    public var expiresAt: Date?
    public var secretKinds: [SecretKind]
    /// For images, GIFs, rich text and files: the pasteboard type of the stored payload, and the private file holding it.
    public var payloadType: String?
    public var payloadFile: String?
    public var favorite: Bool = false
}

/// A stable fingerprint of clipboard text, used to detect duplicates. Never logged.
public func fingerprint(of text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

public func classify(_ text: String) -> ClipKind {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, !t.contains(where: \.isNewline), !t.contains(" "),
          let u = URL(string: t), let scheme = u.scheme?.lowercased(),
          ["http", "https", "ftp", "mailto"].contains(scheme), u.host != nil || scheme == "mailto" else { return .text }
    return .url
}

extension ClipItem {
    /// The one-line title shown in lists: file lists show file names, not full paths.
    public var listTitle: String {
        switch kind {
        case .file:
            return text.split(separator: "\n").map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        default:
            return text
        }
    }
}
