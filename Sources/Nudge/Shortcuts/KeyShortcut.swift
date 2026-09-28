import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: a key code plus Carbon modifier flags.
struct KeyShortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// What to show for the key ("Space", "K"), captured when recorded.
    var keyLabel: String

    static let quickAddDefault = KeyShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        keyLabel: "Space"
    )

    /// "⌘⇧Space" in the standard macOS modifier order (⌃⌥⇧⌘).
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    /// Builds a shortcut from a key press, or nil if it isn't usable globally
    /// (needs ⌘, ⌃ or ⌥, except for function keys).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        let code = Int(event.keyCode)
        let isFunctionKey = Self.functionKeys[code] != nil
        guard isFunctionKey || modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }

        let label = Self.specialKeys[code] ?? Self.functionKeys[code]
            ?? event.charactersIgnoringModifiers?.uppercased()
        guard let label, !label.isEmpty, !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        self.init(keyCode: UInt32(code), carbonModifiers: modifiers, keyLabel: label)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
}
