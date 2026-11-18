import Foundation
import CryptoKit
import Vision

/// Encrypts stored image and file payloads with AES-GCM (CryptoKit). The key lives in the Keychain; the app supplies it.
public struct PayloadCipher: Sendable {
    private let key: SymmetricKey
    public init(key: SymmetricKey) { self.key = key }
    public static func generateKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    public func seal(_ plain: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw CocoaError(.coderInvalidValue) }
        return combined
    }
    public func open(_ sealed: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: sealed) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

/// Reads the text in an image on this Mac (Vision). Nothing leaves the machine.
public enum TextRecognizer {
    public static func recognize(imageData: Data) -> String {
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard (try? handler.perform([request])) != nil else { return "" }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
