import Foundation

/// A global shortcut for one action: a virtual key code and Carbon modifier bits (command 256, shift 512, option 2048, control 4096).
public struct ActionShortcut: Codable, Equatable, Sendable {
    public var keyCode: Int
    public var modifiers: Int
    public init(keyCode: Int, modifiers: Int) { self.keyCode = keyCode; self.modifiers = modifiers }
}

/// Every action that can have its own global shortcut. The picker keeps its own settings fields (hotKeyCode and hotKeyModifiers).
public enum HotAction: String, CaseIterable, Codable, Sendable {
    case picker, history, screenshot, gif, annotate, emoji, pause, stack, pasteNextStack

    /// Whether the shortcut is saved in the picker fields rather than in actionShortcuts.
    public var usesPickerFields: Bool { self == .picker }
}
