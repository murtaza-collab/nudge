import AppKit
import Carbon.HIToolbox

enum HotKeyAction: UInt32, CaseIterable {
    case quickAdd = 1
    case openTasks = 2
    case search = 3

    var title: String {
        switch self {
        case .quickAdd: "Quick Add"
        case .openTasks: "Open Tasks"
        case .search: "Search"
        }
    }
}

enum HotKeyError: Error, Equatable {
    /// An enabled macOS shortcut (Spotlight, input sources, Mission Control…) uses it.
    case reservedBySystem
    /// Already registered within this process. (Registrations by other apps are not
    /// reported by macOS; see ShortcutController.verified.)
    case inUse
    /// Already assigned to another of this app's actions.
    case duplicate(HotKeyAction)
    case failed(OSStatus)

    var message: String {
        switch self {
        case .reservedBySystem: "macOS already uses this shortcut (see System Settings → Keyboard → Keyboard Shortcuts)."
        case .inUse: "This shortcut is already in use."
        case .duplicate(let other): "Already used for \(other.title)."
        case .failed(let status): "This shortcut couldn't be registered (error \(status))."
        }
    }
}

/// System-wide hotkeys via Carbon's RegisterEventHotKey: the only public API for global
/// shortcuts that doesn't need Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [HotKeyAction: EventHotKeyRef] = [:]
    private var handlers: [HotKeyAction: () -> Void] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x4D44_5574 // 'MDUt'

    /// Registers `shortcut` for `action`, replacing any previous one. Nil just unregisters.
    /// On failure the action is left without a shortcut.
    @discardableResult
    func register(_ shortcut: KeyShortcut?, for action: HotKeyAction, handler: @escaping () -> Void) -> HotKeyError? {
        unregister(action)
        guard let shortcut else { return nil }
        installHandlerIfNeeded()

        if Self.isReservedBySystem(shortcut) { return .reservedBySystem }

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        switch status {
        case noErr:
            refs[action] = ref
            handlers[action] = handler
            return nil
        case OSStatus(eventHotKeyExistsErr):
            return .inUse
        default:
            return .failed(status)
        }
    }

    func unregister(_ action: HotKeyAction) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        handlers[action] = nil
    }

    fileprivate func fire(_ rawID: UInt32) {
        guard let action = HotKeyAction(rawValue: rawID) else { return }
        handlers[action]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    /// True when an enabled macOS symbolic hotkey uses the same key and modifiers.
    static func isReservedBySystem(_ shortcut: KeyShortcut) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let array = unmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        let relevantModifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return array.contains { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
                  let modifiers = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value
            else { return false }
            return code == shortcut.keyCode && modifiers & relevantModifiers == shortcut.carbonModifiers & relevantModifiers
        }
    }
}

/// Carbon calls this on the main thread when a registered hotkey is pressed.
private func hotKeyEventHandler(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr else { return status }
    let rawID = id.id
    MainActor.assumeIsolated { HotKeyCenter.shared.fire(rawID) }
    return noErr
}
