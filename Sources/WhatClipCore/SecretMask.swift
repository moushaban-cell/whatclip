import Foundation

/// A preview of a secret that never shows all of it.
/// First draft from a local model showed the MIDDLE of the text and hid the ends, which would leak; rewritten and tested.
public enum SecretMask {
    public static func preview(_ text: String, maxLength: Int = 40) -> String {
        let flat = String(text.map { $0.isNewline ? " " : $0 })
        let chars = Array(flat)
        let limit = max(1, maxLength)
        let shown: String
        if chars.count <= 8 {
            shown = String(repeating: "•", count: chars.count)
        } else {
            let head = String(chars[0..<4])
            let tail = String(chars[(chars.count - 2)...])
            let hidden = min(chars.count - 6, 24)
            shown = head + String(repeating: "•", count: hidden) + tail
        }
        if shown.count <= limit { return shown }
        return String(shown.prefix(limit - 1)) + "…"
    }
}
