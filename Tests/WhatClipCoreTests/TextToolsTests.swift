import Testing
@testable import WhatClipCore

@Suite struct TextToolsTests {
    @Test func caseAndLines() {
        #expect(TextTool.upper.apply("abc") == "ABC")
        #expect(TextTool.trimWhitespace.apply("  x \n") == "x")
        #expect(TextTool.removeDuplicateLines.apply("b\na\nb") == "b\na")
        #expect(TextTool.removeEmptyLines.apply("a\n\n  \nb") == "a\nb")
        #expect(TextTool.sortLines.apply("c\na\nb") == "a\nb\nc")
    }
    @Test func jsonFormatAndMinify() {
        #expect(TextTool.jsonMinify.apply("{ \"a\" : 1 }") == "{\"a\":1}")
        #expect(TextTool.jsonFormat.apply("{\"a\":1}")?.contains("\n") == true)
        #expect(TextTool.jsonFormat.apply("not json") == nil)
    }
    @Test func encodings() {
        #expect(TextTool.urlEncode.apply("a b&c") == "a%20b%26c")
        #expect(TextTool.urlDecode.apply("a%20b") == "a b")
        #expect(TextTool.base64Encode.apply("hi") == "aGk=")
        #expect(TextTool.base64Decode.apply("aGk=") == "hi")
        #expect(TextTool.base64Decode.apply("!!!") == nil)
    }
    @Test func stats() {
        #expect(TextTool.stats.apply("one two\nthree") == "3 words, 13 characters, 2 lines")
    }
    @Test func everyToolHasATitle() { #expect(TextTool.allCases.allSatisfy { !$0.title.isEmpty }) }
}

@Suite struct SmartTests {
    @Test func findsSyntheticValues() {
        let found = SmartRecognizer.find(in: "mail test.user@example.com or call +1 555 010 0199 on 2026-11-18, colour #ff8800, path /usr/local/bin/tool")
        let kinds = found.map(\.kind)
        #expect(kinds.contains(.email) && kinds.contains(.phone) && kinds.contains(.date) && kinds.contains(.hexColor) && kinds.contains(.filePath))
    }
    @Test func ordinaryTextHasNothing() {
        #expect(SmartRecognizer.find(in: "just a sentence with 12 words in it to test").isEmpty)
    }
}
