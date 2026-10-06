import Carbon
import MoliMacCore

extension MouseAction {
    var title: String {
        switch self {
        case .none: "未设置"
        case .lookUp: "查询与快速查看"
        case .missionControl: "调度中心"
        case .appExpose: "应用程序窗口"
        case .showDesktop: "显示桌面"
        case .launchpad: "启动台"
        case .spaceLeft: "切换到左边的桌面"
        case .spaceRight: "切换到右边的桌面"
        case .spotlight: "聚焦搜索"
        case .back: "后退"
        case .forward: "前进"
        case .smartZoom: "智能缩放"
        case .middleClick: "中键点击"
        case let .keyboardShortcut(shortcut): "快捷键 " + shortcut.title
        case .dragSpacesAndMissionControl: "切换桌面与调度中心"
        case .dragScrollAndNavigate: "拖动滚动与翻页"
        case .dragMiddleButton: "中键拖动"
        case .scrollDesktopAndLaunchpad: "桌面与启动台"
        case .scrollZoom: "缩放"
        case .scrollHorizontal: "横向滚动"
        case .scrollSwift: "快速滚动"
        case .scrollPrecise: "精确滚动"
        case let .unknown(name): "不支持的动作（" + name + "）"
        }
    }
}

enum ButtonName {
    static func title(_ button: Int) -> String {
        switch button {
        case 1: "左键"
        case 2: "右键"
        case 3: "中键"
        case 4, 5: "侧键 \(button)"
        default: "按键 \(button)"
        }
    }
}

extension Trigger {
    /// For example "单击", "按住并拖动", "双击后按住并滚动".
    var title: String {
        let counted = ["单击", "双击", "三击"][min(max(clicks, 1), Trigger.maxClicks) - 1]
        let press = switch kind {
        case .click: ""
        case .hold: "按住"
        case .drag: "按住并拖动"
        case .scroll: "按住并滚动"
        }
        switch (clicks, kind) {
        case (_, .click): return counted
        case (1, _): return press
        default: return counted + "后" + press
        }
    }
}

extension KeyboardShortcut {
    /// Modifiers in the order macOS prints them, then the key, for example "⌃⌘D".
    var title: String {
        ModifierKey.allCases.filter(modifiers.contains).map(\.symbol).joined() + KeyNames.name(for: keyCode)
    }
}

/// Names of keys as the current keyboard layout prints them.
enum KeyNames {
    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "⎋", 71: "⌧", 76: "⌤", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func name(for keyCode: UInt16) -> String {
        special[keyCode] ?? translated(keyCode)?.uppercased() ?? "键 \(keyCode)"
    }

    private static func translated(_ keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else {
            return nil
        }
        let text = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
