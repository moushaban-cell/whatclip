import Testing
@testable import WhatClipCore

@Suite struct SecretMaskTests {
    @Test func keepsOnlyEndsOfLongSecrets() {
        let fake = "AKIAABCDEFGHIJKLMNOP"  // synthetic
        let p = SecretMask.preview(fake)
        #expect(p.hasPrefix("AKIA") && p.hasSuffix("OP"))
        #expect(!p.contains("ABCDEFGHIJKLMN"), "the middle must never show")
        #expect(p != fake)
    }
    @Test func shortTextIsFullyHidden() {
        #expect(SecretMask.preview("abcdefgh") == "••••••••")
        #expect(SecretMask.preview("") == "")
    }
    @Test func newlinesFlattenAndLengthIsCapped() {
        let p = SecretMask.preview(String(repeating: "x", count: 100) + "\nend", maxLength: 12)
        #expect(p.count <= 12 && p.hasSuffix("…"))
        #expect(!p.contains("\n"))
    }
}
