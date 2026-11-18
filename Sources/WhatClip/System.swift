import AppKit
import LocalAuthentication
import ServiceManagement
import Security
import CryptoKit
import WhatClipCore

/// The key that encrypts stored images and files. It lives in the login Keychain and is created on first use.
enum KeyStore {
    static let service = "app.whatclip.WhatClip"
    static let account = "payload-key"

    static func loadOrCreateKey() -> SymmetricKey? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = PayloadCipher.generateKey()
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecValueData as String: key.withUnsafeBytes { Data($0) },
                                  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? key : nil
    }
}

/// Touch ID or the Mac password, before the history is shown.
enum Authentication {
    static func unlock(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }   // no password set on this Mac
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in cont.resume(returning: ok) }
        }
    }
}

/// Start at login through the system's login-item service (needs the app in /Applications).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch { return false }
    }
}

/// Screenshot of a selected area, copied to the clipboard by macOS's own screencapture tool; the monitor records it.
enum Screenshot {
    static func captureArea() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-c"]
        try? p.run()
    }
}
