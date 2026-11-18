import Testing
@testable import WhatClipCore

@Suite struct MergeTests {
    @Test func joinsWithSeparatorsAndSkipsEmpty() {
        #expect(Merge.join(["a", "", "b\n"], separator: .comma) == "a, b")
        #expect(Merge.join(["a", "b"], separator: .newline) == "a\nb")
        #expect(Merge.join(["a", "b"], separator: .none) == "ab")
        #expect(Merge.join([], separator: .space) == "")
    }
}

@Suite struct UserActionTests {
    @Test func parsesAndFormats() {
        let parsed = UserAction.parse("Upper | tr a-z A-Z\nbad line\nSort | sort\n | empty")
        #expect(parsed == [UserAction(name: "Upper", command: "tr a-z A-Z"), UserAction(name: "Sort", command: "sort")])
        #expect(UserAction.parse(UserAction.format(parsed)) == parsed)
    }
}
