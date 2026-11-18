import Carbon.HIToolbox
import AppKit

/// A global shortcut through the Carbon hot-key API, which needs no special permission.
/// Each HotKey has its own id. One event handler is installed for all of them and runs the action registered under the id that fired.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var lastID: UInt32 = 0
    private let id: UInt32

    init() { Self.lastID += 1; id = Self.lastID }

    /// The status of the last registration, in plain words, for the Settings window.
    private(set) var lastStatus = "Not registered yet."

    /// Removes this shortcut, if any.
    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.handlers[id] = nil
    }

    /// Returns false when the shortcut is already taken by another app (or is not valid). The reason is in `lastStatus`.
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        unregister()
        Self.handlers[id] = action
        if !Self.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var fired = EventHotKeyID()
                let got = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                            nil, MemoryLayout<EventHotKeyID>.size, nil, &fired)
                guard got == noErr else { return noErr }
                let number = fired.id
                DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.handlers[number]?() } }
                return noErr
            }, 1, &spec, nil, nil)
            Self.installed = true
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x43444154), id: id)
        let rc = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if rc == noErr {
            lastStatus = "Active."
        } else if rc == eventHotKeyExistsErr {
            lastStatus = "Another app already uses this shortcut. Choose a different one."
        } else {
            lastStatus = "Could not register this shortcut (system error \(rc))."
        }
        NSLog("WhatClip hotkey: %@", lastStatus)
        return rc == noErr
    }
}
