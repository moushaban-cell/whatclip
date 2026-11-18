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
/// One successful unlock is remembered for `sessionLength`, across the picker and the history window, so you are not asked on every open.
/// "Lock history now" in the menu forgets it at once.
@MainActor
enum Authentication {
    static let sessionLength: TimeInterval = 15 * 60
    private static var unlockedUntil: Date?

    static var isUnlocked: Bool { (unlockedUntil ?? .distantPast) > Date() }

    static func lockNow() { unlockedUntil = nil }

    static func unlock(reason: String) async -> Bool {
        if isUnlocked { return true }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }   // no password set on this Mac
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in cont.resume(returning: ok) }
        }
        if ok { unlockedUntil = Date().addingTimeInterval(sessionLength) }
        return ok
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

/// Pastes the chosen item into the app the person was using. Needs the Accessibility permission for WhatClip.
/// Without it, the item stays on the clipboard and the person presses ⌘V.
@MainActor
enum AutoPaste {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its Accessibility prompt (once per launch is enough; WhatClip then appears in the list to switch on).
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static var askedThisLaunch = false
    /// Asks for the permission once per launch. Later pastes without it do not open the settings again;
    /// the item simply stays on the clipboard for ⌘V.
    static func askOnce() {
        guard !askedThisLaunch else { return }
        askedThisLaunch = true
        requestTrust()
    }

    /// Brings the previous app forward, then sends ⌘V to it.
    static func paste(into app: NSRunningApplication?) {
        // Forces the app the person was using to the front, then sends ⌘V only once that app really has focus.
        // ⌘V is never sent while WhatClip itself is in front: that is how the picker and main window were opening.
        app?.activate(options: [.activateIgnoringOtherApps])
        waitForFocus(app, attempts: 40)
    }

    private static func waitForFocus(_ target: NSRunningApplication?, attempts: Int) {
        let front = NSWorkspace.shared.frontmostApplication
        let ownID = Bundle.main.bundleIdentifier
        if let target, front?.processIdentifier == target.processIdentifier {
            postCommandV()
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { waitForFocus(target, attempts: attempts - 1) }
        } else if front?.bundleIdentifier != ownID {
            postCommandV()                    // another app took focus: paste there
        }
        // Otherwise WhatClip still has focus and nothing is sent; the item stays on the clipboard for ⌘V.
    }

    /// Sends ⌘V to whatever app is in front.
    static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }
}
