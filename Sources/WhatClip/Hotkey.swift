import Carbon.HIToolbox
import AppKit

/// A global shortcut through the Carbon hot-key API, which needs no special permission.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handler: (() -> Void)?
    private static var installed = false

    /// Removes the current shortcut, if any.
    func unregister() { if let ref { UnregisterEventHotKey(ref) }; ref = nil }

    /// The status of the last registration, in plain words, for the Settings window.
    private(set) var lastStatus = "Not registered yet."

    /// Returns false when the shortcut is already taken by another app (or is not valid). The reason is in `lastStatus`.
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: UInt32 = UInt32(cmdKey | shiftKey), action: @escaping () -> Void) -> Bool {
        unregister()
        Self.handler = action
        if !Self.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.handler?() } }; return noErr }, 1, &spec, nil, nil)
            Self.installed = true
        }
        let id = EventHotKeyID(signature: OSType(0x43444154), id: 1)
        let rc = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if rc == noErr {
            lastStatus = "Active. Press the shortcut from any app to open the picker."
        } else if rc == eventHotKeyExistsErr {
            lastStatus = "Another app already uses this shortcut. Choose a different one."
        } else {
            lastStatus = "Could not register this shortcut (system error \(rc))."
        }
        NSLog("WhatClip hotkey: %@", lastStatus)
        return rc == noErr
    }
}
