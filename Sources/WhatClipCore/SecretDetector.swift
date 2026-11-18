import Foundation

// First draft written by a local model (qwen2.5-coder:7b) and then corrected and tested by hand.

public enum SecretKind: String, Sendable, CaseIterable {
    case awsAccessKey, githubToken, slackToken, stripeKey, googleApiKey, jwt, privateKeyBlock, creditCard, bearerToken
}

public struct SecretFinding: Sendable, Equatable {
    public let kind: SecretKind
}

/// Spots text that looks like a credential, so it can be skipped or removed automatically.
/// Works on shape only: it can say "looks like a GitHub token", not "is a live token".
public enum SecretDetector {
    private static let patterns: [(SecretKind, String)] = [
        (.awsAccessKey, #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#),
        (.githubToken, #"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b|\bgithub_pat_[A-Za-z0-9_]{50,}\b"#),
        (.slackToken, #"\bxox[baprs]-[A-Za-z0-9-]{10,}"#),
        (.stripeKey, #"\b(sk|rk)_(live|test)_[A-Za-z0-9]{16,}\b"#),
        (.googleApiKey, #"\bAIza[0-9A-Za-z_-]{35}"#),
        (.jwt, #"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#),
        (.privateKeyBlock, #"-----BEGIN ([A-Z]+ )?PRIVATE KEY-----"#),
        (.bearerToken, #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{20,}"#),
    ]
    // Digit runs of 13-19 digits that may be split by single spaces or dashes.
    private static let cardPattern = #"(?<![0-9])[0-9](?:[ -]?[0-9]){12,18}(?![0-9])"#

    private static func compile(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

    public static func scan(_ text: String) -> [SecretFinding] {
        guard !text.isEmpty else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        var found = Set<SecretKind>()
        for (kind, p) in patterns where compile(p).firstMatch(in: text, range: whole) != nil { found.insert(kind) }
        for m in compile(cardPattern).matches(in: text, range: whole) {
            guard let r = Range(m.range, in: text) else { continue }
            let digits = text[r].filter(\.isNumber)
            if (13...19).contains(digits.count), "3456".contains(digits.first!), luhn(digits) { found.insert(.creditCard); break }
        }
        return SecretKind.allCases.filter(found.contains).map(SecretFinding.init(kind:))
    }

    static func luhn(_ digits: String) -> Bool {
        var sum = 0, alt = false
        for c in digits.reversed() {
            guard var d = c.wholeNumberValue else { return false }
            if alt { d *= 2; if d > 9 { d -= 9 } }
            sum += d; alt.toggle()
        }
        return sum % 10 == 0
    }
}
