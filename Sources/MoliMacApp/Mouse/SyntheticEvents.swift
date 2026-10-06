import Carbon
import CoreGraphics
import MoliMacCore

/// Events MoliMac posts itself. Each carries `marker` in `eventSourceUserData`, so
/// MoliMac's own taps let them through instead of handling them a second time.
enum SyntheticEvents {
    /// "MoliMac" in ASCII.
    static let marker: Int64 = 0x4D_6F6C_694D_6163

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    private static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    private static var pointerLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// The modifier keys held right now.
    static var currentFlags: CGEventFlags {
        CGEventSource.flagsState(.combinedSessionState)
    }

    // MARK: - Mouse

    /// Presses and releases `button` (1 = left) `count` times, as one multi-click.
    static func postClicks(button: Int, count: Int) {
        for clickState in 1...max(count, 1) {
            postMouse(button: button, down: true, clickState: clickState)
            postMouse(button: button, down: false, clickState: clickState)
        }
    }

    static func postMouse(button: Int, down: Bool, clickState: Int = 1) {
        guard let cgButton = CGMouseButton(rawValue: UInt32(button - 1)) else {
            return
        }
        let type: CGEventType = switch button {
        case 1: down ? .leftMouseDown : .leftMouseUp
        case 2: down ? .rightMouseDown : .rightMouseUp
        default: down ? .otherMouseDown : .otherMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: pointerLocation,
            mouseButton: cgButton
        ) else {
            return
        }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event.flags = currentFlags
        mark(event)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard

    static func post(_ shortcut: KeyboardShortcut) {
        postKey(shortcut.keyCode, flags: flags(for: shortcut.modifiers))
    }

    /// Presses and releases a key with exactly `flags` held, then tells apps which
    /// modifiers are really down, so none look stuck afterwards.
    static func postKey(_ keyCode: UInt16, flags: CGEventFlags) {
        // Key codes mean different keys on ANSI, ISO and JIS keyboards; posting
        // with the attached keyboard's type keeps the code the user recorded.
        let keyboardType = Int64(LMGetKbdType())
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else {
                return
            }
            event.flags = flags
            event.setIntegerValueField(.keyboardEventKeyboardType, value: keyboardType)
            mark(event)
            event.post(tap: .cghidEventTap)
        }
        if let reset = CGEvent(source: nil) {
            reset.type = .flagsChanged
            reset.flags = currentFlags
            mark(reset)
            reset.post(tap: .cghidEventTap)
        }
    }

    static func flags(for modifiers: Set<ModifierKey>) -> CGEventFlags {
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier {
            case .control: flags.insert(.maskControl)
            case .option: flags.insert(.maskAlternate)
            case .shift: flags.insert(.maskShift)
            case .command: flags.insert(.maskCommand)
            }
        }
        return flags
    }
}
