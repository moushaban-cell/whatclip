import Testing
import Foundation
import CryptoKit
@testable import WhatClipCore

@Suite struct SecurityTests {
    @Test func cipherRoundTripsAndRejectsOtherKeys() throws {
        let c = PayloadCipher(key: PayloadCipher.generateKey())
        let sealed = try c.seal(Data("synthetic payload".utf8))
        #expect(c.open(sealed) == Data("synthetic payload".utf8))
        #expect(PayloadCipher(key: PayloadCipher.generateKey()).open(sealed) == nil)
    }
    @Test func encryptedPayloadsAreOpaqueOnDiskAndReadableWithTheKey() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("wc-enc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: d) }
        let s = try ClipStore(path: d.appendingPathComponent("h.sqlite").path)
        s.cipher = PayloadCipher(key: PayloadCipher.generateKey()); s.encryptNew = true
        let plain = Data("SYNTHETIC-PLAIN-BYTES".utf8)
        let item = try s.add(kind: .file, label: "x", payload: plain, payloadType: "public.data")
        let url = try #require(s.payloadURL(for: item))
        #expect(url.lastPathComponent.hasSuffix(".enc"))
        #expect(try Data(contentsOf: url) != plain)
        #expect(s.payloadData(for: item) == plain)
    }
    @Test func ocrTextIsSearchable() throws {
        let s = try ClipStore()
        _ = try s.add(kind: .image, label: "Image", payload: Data([1, 2, 3]), payloadType: "public.png", ocr: "invoice total 4200 EUR")
        #expect(try s.list(query: "invoice").count == 1)
        #expect(try s.list(query: "missing words").isEmpty)
    }
    @Test func recognizerReturnsStringForNonImages() {
        #expect(TextRecognizer.recognize(imageData: Data([0, 1, 2])) == "")
    }
}

@Suite struct TextEncryptionTests {
    @Test func textIsSealedOnDiskAndStillSearchable() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("wc-txt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: d) }
        let path = d.appendingPathComponent("h.sqlite").path
        let s = try ClipStore(path: path)
        s.cipher = PayloadCipher(key: PayloadCipher.generateKey()); s.encryptNew = true
        _ = try s.add(text: "SYNTHETIC-SECRET-WORDING launch plan")
        let raw = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(raw.range(of: Data("SYNTHETIC-SECRET-WORDING".utf8)) == nil, "plain text must not be in the database file")
        #expect(try s.list(query: "launch").count == 1)
        #expect(try s.list(query: "missing").isEmpty)
        #expect(try s.list().first?.text == "SYNTHETIC-SECRET-WORDING launch plan")
    }
}
