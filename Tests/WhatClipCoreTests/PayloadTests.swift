import Testing
import Foundation
@testable import WhatClipCore

@Suite struct PayloadTests {
    func dir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("wc-pl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    @Test func imageIsStoredPrivatelyAndDedupedByContent() throws {
        let d = try dir(); defer { try? FileManager.default.removeItem(at: d) }
        let s = try ClipStore(path: d.appendingPathComponent("h.sqlite").path)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])          // synthetic bytes, not a real image
        let a = try s.add(kind: .image, label: "Image 4 × 4", payload: png, payloadType: "public.png")
        let b = try s.add(kind: .image, label: "Image 4 × 4", payload: png, payloadType: "public.png")
        #expect(a.id == b.id && b.useCount == 2)
        let url = try #require(s.payloadURL(for: b))
        #expect(try Data(contentsOf: url) == png)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
    @Test func deletingRemovesThePayloadFile() throws {
        let d = try dir(); defer { try? FileManager.default.removeItem(at: d) }
        let s = try ClipStore(path: d.appendingPathComponent("h.sqlite").path)
        let it = try s.add(kind: .gif, label: "GIF", payload: Data([1, 2, 3]), payloadType: "com.compuserve.gif")
        let url = try #require(s.payloadURL(for: it))
        try s.delete(it.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
    @Test func retentionRemovesOldPayloads() throws {
        let d = try dir(); defer { try? FileManager.default.removeItem(at: d) }
        let s = try ClipStore(path: d.appendingPathComponent("h.sqlite").path)
        _ = try s.add(kind: .richText, label: "Rich", payload: Data([9, 9]), payloadType: "public.rtf")
        try s.add(text: "newer")
        try s.enforceRetention(maxItems: 1, maxAgeDays: nil)
        #expect(try s.count() == 1)
        let blobs = try FileManager.default.contentsOfDirectory(atPath: d.appendingPathComponent("blobs").path)
        #expect(blobs.isEmpty)
    }
    @Test func textHasNoPayloadAndKindsAreDistinct() throws {
        let s = try ClipStore()
        let t = try s.add(text: "https://example.com")
        #expect(t.payloadFile == nil && t.kind == .url)
        #expect(ClipKind.allCases.count == 6)
    }
}
