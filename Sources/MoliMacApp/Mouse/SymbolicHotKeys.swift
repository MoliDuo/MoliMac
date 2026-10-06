import CoreGraphics
import Darwin
import MoliMacCore

/// Triggers system shortcuts (Mission Control, Look Up and so on) by posting the key
/// the user has bound to them, which is what macOS reacts to.
///
/// The bindings are read with private CoreGraphics functions, loaded at run time so
/// a missing symbol turns the action off instead of keeping the app from launching.
enum SymbolicHotKeys {
    private typealias GetValue = @convention(c) (
        UInt32,
        UnsafeMutablePointer<UInt16>,
        UnsafeMutablePointer<UInt16>,
        UnsafeMutablePointer<UInt64>
    ) -> Int32
    private typealias SetValue = @convention(c) (UInt32, UInt16, UInt16, UInt64) -> Int32
    private typealias IsEnabled = @convention(c) (UInt32) -> Bool
    private typealias SetEnabled = @convention(c) (UInt32, Bool) -> Int32

    private struct Functions {
        let getValue: GetValue
        let setValue: SetValue
        let isEnabled: IsEnabled
        let setEnabled: SetEnabled
    }

    private static let functions: Functions? = {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        func load<T>(_ name: String, as _: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else {
                Log.actions.error("missing \(name, privacy: .public)")
                return nil
            }
            return unsafeBitCast(symbol, to: T.self)
        }
        guard
            let getValue = load("CGSGetSymbolicHotKeyValue", as: GetValue.self),
            let setValue = load("CGSSetSymbolicHotKeyValue", as: SetValue.self),
            let isEnabled = load("CGSIsSymbolicHotKeyEnabled", as: IsEnabled.self),
            let setEnabled = load("CGSSetSymbolicHotKeyEnabled", as: SetEnabled.self)
        else {
            return nil
        }
        return Functions(getValue: getValue, setValue: setValue, isEnabled: isEnabled, setEnabled: setEnabled)
    }()

    static func post(_ hotKey: SymbolicHotKey) {
        guard let functions else {
            return
        }
        let id = UInt32(hotKey.rawValue)
        var keyEquivalent: UInt16 = 0
        var keyCode: UInt16 = 0
        // Some systems store the flags in 32 bits; the upper half then stays zero.
        var modifierFlags: UInt64 = 0
        var current: SymbolicHotKeyBinding?
        if functions.getValue(id, &keyEquivalent, &keyCode, &modifierFlags) == 0 {
            current = SymbolicHotKeyBinding(
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                isEnabled: functions.isEnabled(id)
            )
        }

        let (binding, rebind) = hotKey.binding(toPost: current)
        if rebind {
            // Lasts until logout; the user's saved shortcut settings are not touched.
            _ = functions.setValue(id, SymbolicHotKeyBinding.noKey, binding.keyCode, binding.modifierFlags)
            _ = functions.setEnabled(id, true)
            Log.actions.info("bound system shortcut \(id) to key \(binding.keyCode)")
        }
        SyntheticEvents.postKey(binding.keyCode, flags: CGEventFlags(rawValue: binding.modifierFlags))
    }
}
