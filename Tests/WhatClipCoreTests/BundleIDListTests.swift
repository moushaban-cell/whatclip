import Testing
@testable import WhatClipCore

@Suite struct BundleIDListTests {
    @Test func parsesLinesCommasAndSpaces() {
        #expect(BundleIDList.parse("com.apple.keychainaccess\ncom.1password.1password, org.example.vault  net.test-app_2") ==
            ["com.apple.keychainaccess", "com.1password.1password", "org.example.vault", "net.test-app_2"])
    }
    @Test func dropsEmptyDuplicatesAndBadCharacters() {
        #expect(BundleIDList.parse("a.b\n\n a.b ,, c/d e!f") == ["a.b"])
        #expect(BundleIDList.parse("") == [])
    }
    @Test func dropsOverlongIDs() {
        let long = String(repeating: "a", count: 256)
        #expect(BundleIDList.parse(long + " ok.id") == ["ok.id"])
    }
    @Test func formatSortsAndHasNoTrailingNewline() {
        #expect(BundleIDList.format(["z.app", "a.app", "a.app"]) == "a.app\nz.app")
        #expect(BundleIDList.format([]) == "")
    }
    @Test func roundTrips() {
        let ids = ["com.a.b", "org.c"]
        #expect(BundleIDList.parse(BundleIDList.format(ids)).sorted() == ids.sorted())
    }
}
