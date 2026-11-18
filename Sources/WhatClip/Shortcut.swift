import AppKit

/// Records a new picker shortcut: the next key combination with Command, Option or Control (Escape cancels).
/// Used by the welcome tour and the Settings window. The caller saves the result and re-registers the hot key.
@MainActor
final class ShortcutRecorder {
    private var monitor: Any?

    /// Starts listening. `onRecord` gets the key code and Carbon modifier bits; `onCancel` runs on Escape.
    func start(onRecord: @escaping (Int, Int) -> Void, onCancel: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.stop(); onCancel(); return nil }
            let f = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard f.contains(.command) || f.contains(.option) || f.contains(.control) else { return nil }
            var carbon = 0
            if f.contains(.command) { carbon |= 256 }
            if f.contains(.shift) { carbon |= 512 }
            if f.contains(.option) { carbon |= 2048 }
            if f.contains(.control) { carbon |= 4096 }
            self.stop()
            onRecord(Int(e.keyCode), carbon)
            return nil
        }
    }
    func stop() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }

    /// A readable name for a shortcut, for example "⌘X".
    static func describe(code: Int, mods: Int) -> String { SettingsWindowController.describe(code: code, mods: mods) }
}
