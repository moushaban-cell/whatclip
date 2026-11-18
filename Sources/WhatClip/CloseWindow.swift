import AppKit

/// A window that closes on Escape, like a standard macOS sheet or dialog.
final class CloseWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(nil) }
}
