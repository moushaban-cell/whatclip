import Testing
import Foundation
@testable import WhatClipCore

@Suite struct UpdateScriptTests {
    @Test func refusesAnythingThatIsNotPlainVersionNumbers() {
        #expect(UpdateScript.make(version: "1.0.1") != nil)
        #expect(UpdateScript.make(version: "1.0; rm -rf ~") == nil)
        #expect(UpdateScript.make(version: "$(id)") == nil)
        #expect(UpdateScript.make(version: "1.0.\n1") == nil)
        #expect(UpdateScript.make(version: "") == nil)
        #expect(UpdateScript.make(version: ".1") == nil)
    }

    @Test func scriptDownloadsOverHTTPSAndChecksBeforeInstalling() throws {
        let script = try #require(UpdateScript.make(version: "1.2.3"))
        #expect(script.contains("https://github.com/moushaban-cell/whatclip/releases/download/v1.2.3/WhatClip-1.2.3.zip"))
        #expect(script.contains("--proto '=https'"))
        #expect(script.contains("shasum -a 256"))
        #expect(script.contains("does not match. Nothing was installed"))
        #expect(script.contains("CFBundleIdentifier"))
        #expect(script.contains(UpdateScript.bundleID))
        // The checksum must be checked before the app is moved.
        let check = try #require(script.range(of: "does not match"))
        let move = try #require(script.range(of: "mv \"/Applications/WhatClip.app\""))
        #expect(check.lowerBound < move.lowerBound)
    }

    @Test func generatedScriptIsValidShell() throws {
        let script = try #require(UpdateScript.make(version: "1.2.3"))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("whatclip-syntax-\(UUID().uuidString).sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-n", file.path]
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }
}
