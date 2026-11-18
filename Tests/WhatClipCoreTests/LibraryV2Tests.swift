import Testing
import Foundation
@testable import WhatClipCore

@Suite struct LibraryV2Tests {
    @Test func tagsFilterAndLibraryRules() throws {
        let s = try ClipStore()
        let a = try s.add(text: "design notes"); let b = try s.add(text: "invoice 42")
        try s.setTags(a.id, ["Work", "work", " design ", ""])
        #expect(s.tags(for: a.id) == ["design", "work"])
        #expect(try s.list(filter: .init(tag: "work")).map(\.text) == ["design notes"])
        try s.setFavorite(b.id, true)
        try s.clear()                                   // favourites are part of the Library and survive clear
        #expect(try s.list().map(\.text) == ["invoice 42"])
    }
    @Test func ocrFilter() throws {
        let s = try ClipStore()
        _ = try s.add(kind: .image, label: "Image", payload: Data([1]), payloadType: "public.png", ocr: "total 99")
        _ = try s.add(kind: .image, label: "Image", payload: Data([2]), payloadType: "public.png")
        #expect(try s.list(filter: .init(hasText: true)).count == 1)
    }
    @Test func exportAndImportRoundTrip() throws {
        let s = try ClipStore()
        let t = try s.add(text: "portable note", sourceBundleID: "com.example.app")
        try s.setPinned(t.id, true); try s.setTags(t.id, ["keep"])
        let data = try Transfer.export(s)
        let other = try ClipStore()
        #expect(try Transfer.importData(data, into: other) == 1)
        let back = try other.list()
        #expect(back.first?.text == "portable note" && back.first?.pinned == true && other.tags(for: back[0].id) == ["keep"])
        #expect(throws: (any Error).self) { try Transfer.importData(Data("{}".utf8), into: other) }
    }
}

@Suite struct SnippetTagsAndBoardColourTests {
    @Test func snippetTagsSearchAndSave() throws {
        let s = try ClipStore()
        var a = try s.addSnippet(title: "Thanks", body: "Thank you {{name}}")
        a.tags = "email, polite"; try s.updateSnippet(a)
        #expect(try s.snippets(query: "polite").map(\.title) == ["Thanks"])
        #expect(try s.snippets().first?.tags == "email, polite")
    }
    @Test func boardColourCanBeChanged() throws {
        let s = try ClipStore()
        let b = try s.addBoard(name: "Work", color: "blue")
        try s.updateBoard(b.id, name: "Work 2", color: .amber)
        #expect(try s.boards().first == Board(id: b.id, name: "Work 2", colorName: "amber"))
        #expect(BoardColor.allCases.count == 6)
    }
}
