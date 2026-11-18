import Testing
import Foundation
@testable import WhatClipCore

@Suite struct TemplateTests {
    @Test func findsVariablesInOrderOnce() {
        #expect(Template.variables(in: "Hi {{ name }}, {{company}} and {{name}} {{ }}") == ["name", "company"])
    }
    @Test func rendersAndLeavesMissingAlone() {
        #expect(Template.render("Hi {{name}}, {{topic}}", values: ["name": "Ada"]) == "Hi Ada, {{topic}}")
        #expect(Template.render("no vars", values: [:]) == "no vars")
    }
}

@Suite struct LibraryStoreTests {
    @Test func snippetsRoundTripAndSearch() throws {
        let s = try ClipStore()
        let a = try s.addSnippet(title: "Reply", body: "Thanks {{name}}", folder: "mail")
        _ = try s.addSnippet(title: "Sig", body: "Regards")
        #expect(try s.snippets(query: "thanks").map(\.id) == [a.id])
        var edited = a; edited.favorite = true; edited.title = "Reply 2"; try s.updateSnippet(edited)
        #expect(try s.snippets().first?.title == "Reply 2")
        try s.deleteSnippet(a.id)
        #expect(try s.snippets().count == 1)
    }
    @Test func boardsHoldItemsAndDropThemWhenDeleted() throws {
        let s = try ClipStore()
        let it = try s.add(text: "keep this")
        let b = try s.addBoard(name: "Work", color: "green")
        try s.addToBoard(item: it.id, board: b.id)
        try s.addToBoard(item: it.id, board: b.id)
        #expect(try s.items(onBoard: b.id).map(\.text) == ["keep this"])
        #expect(try s.boards().map(\.name) == ["Work"])
        try s.delete(it.id)
        #expect(try s.items(onBoard: b.id).isEmpty)
        try s.deleteBoard(b.id)
        #expect(try s.boards().isEmpty)
    }
}

@Suite struct FilterTests {
    final class Clock: @unchecked Sendable { var t = Date(timeIntervalSince1970: 1_800_000_000) }
    @Test func favouritesDatesAndAppsFilter() throws {
        let c = Clock()
        let s = try ClipStore(now: { c.t })
        let a = try s.add(text: "old from Notes", sourceBundleID: "com.apple.Notes")
        c.t.addTimeInterval(7200)
        _ = try s.add(text: "new from Safari", sourceBundleID: "com.apple.Safari")
        try s.setFavorite(a.id, true)
        #expect(try s.list(filter: .init(favoritesOnly: true)).map(\.text) == ["old from Notes"])
        #expect(try s.list(filter: .init(source: "com.apple.Safari")).map(\.text) == ["new from Safari"])
        #expect(try s.list(filter: .init(since: c.t.addingTimeInterval(-3600))).map(\.text) == ["new from Safari"])
        #expect(try s.sourceApps() == ["com.apple.Safari", "com.apple.Notes"])
        let b = try s.add(text: "batch one"); let d = try s.add(text: "batch two")
        try s.delete([b.id, d.id])
        #expect(try s.list().map(\.text) == ["new from Safari", "old from Notes"])
    }

    @Test func removingFromABoardKeepsTheItemInHistory() throws {
        let s = try ClipStore()
        let it = try s.add(text: "stays in history")
        let b = try s.addBoard(name: "Ideas", color: "blue")
        try s.addToBoard(item: it.id, board: b.id)
        try s.removeFromBoard(item: it.id, board: b.id)
        #expect(try s.items(onBoard: b.id).isEmpty)
        #expect(try s.list().map(\.text) == ["stays in history"])
    }

    @Test func deletingABoardKeepsItsItemsInHistory() throws {
        let s = try ClipStore()
        let it = try s.add(text: "kept after board delete")
        let b = try s.addBoard(name: "Temp", color: "amber")
        try s.addToBoard(item: it.id, board: b.id)
        try s.deleteBoard(b.id)
        #expect(try s.boards().isEmpty)
        #expect(try s.list().map(\.text) == ["kept after board delete"])
    }

    @Test func clearKeepsPinnedAndFavouriteItems() throws {
        let s = try ClipStore()
        let pinned = try s.add(text: "pinned one")
        let fav = try s.add(text: "favourite one")
        _ = try s.add(text: "plain one")
        try s.setPinned(pinned.id, true)
        try s.setFavorite(fav.id, true)
        try s.clear()
        #expect(Set(try s.list().map(\.text)) == ["pinned one", "favourite one"])
    }

    @Test func newestCopyIgnoresPinningSoTheStackSeesNewCopies() throws {
        let s = try ClipStore()
        let pinned = try s.add(text: "pinned earlier")
        try s.setPinned(pinned.id, true)
        let fresh = try s.add(text: "copied just now")
        #expect(try s.newestCopy()?.id == fresh.id)
        #expect(try s.list(limit: 1).first?.id == pinned.id)   // list still shows pinned first
    }
}
