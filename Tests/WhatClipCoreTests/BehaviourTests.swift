import Testing
import Foundation
@testable import WhatClipCore

@Suite struct FuzzyTests {
    @Test func subsequenceAndCase() {
        #expect(FuzzyMatch.matches("cpy", in: "Clipboard Copy"))
        #expect(!FuzzyMatch.matches("zq", in: "Clipboard"))
        #expect(FuzzyMatch.matches("", in: "anything"))
        #expect(FuzzyMatch.matches("b c", in: "abc"))
    }
}

@Suite struct PasteFormatTests {
    @Test func formats() {
        #expect(PasteFormat.plainText.apply("a\r\nb") == "a\nb")
        #expect(PasteFormat.prettyJSON.apply("{\"a\":1}").contains("\n"))
        #expect(PasteFormat.prettyJSON.apply("plain") == "plain")
        #expect(PasteFormat.markdownLink.apply("https://example.com") == "[https://example.com](https://example.com)")
        #expect(PasteFormat.markdownLink.apply("not a link") == "not a link")
        #expect(PasteFormat.original.apply("x") == "x")
        #expect(PasteFormat.markdown.apply("a\n\n  b  \n") == "a\n\nb")
    }
}

@Suite struct IgnoreTests {
    @Test func regexAndTypes() {
        var p = PrivacyPolicy()
        p.ignoredPatterns = IgnorePatterns(["^otp-\\d{6}$", "(["])   // second pattern is invalid and must be skipped
        #expect(p.decide(text: "otp-123456", types: [], sourceBundleID: nil) == .skip(.excludedApp))
        #expect(p.decide(text: "otp-12", types: [], sourceBundleID: nil) == .capture)
        p.ignoredTypes = ["com.example.private"]
        #expect(p.decide(text: "hello", types: ["com.example.private"], sourceBundleID: nil) == .skip(.concealed))
    }
}
