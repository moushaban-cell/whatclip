import Testing
@testable import WhatClipCore

// All values below are synthetic and not valid credentials.
@Suite struct DetectorTests {
    func kinds(_ s: String) -> [SecretKind] { SecretDetector.scan(s).map(\.kind) }
    @Test func detectsEachShape() {
        #expect(kinds("key AKIAABCDEFGHIJKLMNOP end") == [.awsAccessKey])
        #expect(kinds("ghp_" + String(repeating: "a", count: 36)) == [.githubToken])
        #expect(kinds("github_pat_" + String(repeating: "B", count: 60)) == [.githubToken])
        #expect(kinds("xoxb-1234567890-abcdefghij") == [.slackToken])
        #expect(kinds("sk_live_" + String(repeating: "a1", count: 12)) == [.stripeKey])
        #expect(kinds("AIza" + String(repeating: "a", count: 35)) == [.googleApiKey])
        #expect(kinds("eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.abcdefghijkl") == [.jwt])
        #expect(kinds("-----BEGIN RSA PRIVATE KEY-----\nabc") == [.privateKeyBlock])
        #expect(kinds("Authorization: Bearer abcdefghijklmnopqrstuvwx") == [.bearerToken])
    }
    @Test func cardNumbersNeedLuhn() {
        #expect(kinds("4111 1111 1111 1111") == [.creditCard])
        #expect(kinds("4111-1111-1111-1111") == [.creditCard])
        #expect(kinds("4111 1111 1111 1112") == [], "fails Luhn")
        #expect(kinds("1234567890123456") == [], "does not start with 3-6 and fails Luhn")
    }
    @Test func ordinaryTextIsClean() {
        for s in ["hello world", "Call me on 555-123-4567", "Meeting 2026-11-17 at 10:30", "order #12345678", "https://example.com/path?x=1", "let a = 42", ""] {
            #expect(kinds(s) == [], "\(s)")
        }
    }
    @Test func reportsEachKindOnce() {
        #expect(kinds("AKIAABCDEFGHIJKLMNOP AKIAZZZZZZZZZZZZZZZZ") == [.awsAccessKey])
    }
}
