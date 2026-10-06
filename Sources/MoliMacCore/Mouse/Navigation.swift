import Foundation

/// How "back" and "forward" reach each app. There is no single event every app
/// understands, so the method depends on the app under the pointer.
public enum NavigationMethod: Equatable, Sendable {
    /// A trackpad swipe between pages. Apple's own apps follow it.
    case swipe
    /// Mouse buttons 4 and 5. Most other apps follow them.
    case mouseButtons
    /// App-specific shortcuts.
    case keys(back: KeyboardShortcut, forward: KeyboardShortcut)

    private static let leftBracket: UInt16 = 33
    private static let rightBracket: UInt16 = 30
    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124

    private static let commandBrackets = NavigationMethod.keys(
        back: KeyboardShortcut(keyCode: leftBracket, modifiers: [.command]),
        forward: KeyboardShortcut(keyCode: rightBracket, modifiers: [.command])
    )
    private static let commandArrows = NavigationMethod.keys(
        back: KeyboardShortcut(keyCode: leftArrow, modifiers: [.command]),
        forward: KeyboardShortcut(keyCode: rightArrow, modifiers: [.command])
    )
    private static let optionCommandBrackets = NavigationMethod.keys(
        back: KeyboardShortcut(keyCode: leftBracket, modifiers: [.option, .command]),
        forward: KeyboardShortcut(keyCode: rightBracket, modifiers: [.option, .command])
    )

    /// Apps whose navigation differs from the rule for their vendor.
    private static let overrides: [String: NavigationMethod] = [
        "com.apple.Music": commandBrackets,
        "com.apple.Preview": commandBrackets,
        "com.apple.systempreferences": commandBrackets,
        "com.apple.AppStore": commandBrackets,
        "com.apple.iCal": commandArrows,
        "com.adobe.Acrobat.Pro": commandArrows,
        "com.apple.Notes": optionCommandBrackets,
        "com.apple.freeform": optionCommandBrackets,
        "com.operasoftware.Opera": .swipe,
        "com.binarynights.ForkLift": .swipe,
    ]

    public static func forApp(bundleIdentifier: String?) -> NavigationMethod {
        guard let bundleIdentifier else {
            return .mouseButtons
        }
        if let override = overrides[bundleIdentifier] {
            return override
        }
        return bundleIdentifier.hasPrefix("com.apple.") ? .swipe : .mouseButtons
    }
}

/// System shortcuts macOS lets apps trigger by number ("symbolic hot keys").
public enum SymbolicHotKey: Int, Sendable {
    case missionControl = 32
    case appExpose = 33
    case showDesktop = 36
    case spotlight = 64
    case lookUp = 70
    case spaceLeft = 79
    case spaceRight = 81
    case launchpad = 160

    /// A key code no keyboard produces, bound to the shortcut when the user's own
    /// binding cannot be typed on the current layout.
    public var unreachableKeyCode: UInt16 {
        UInt16(rawValue + 400)
    }

    public init?(action: MouseAction) {
        switch action {
        case .missionControl: self = .missionControl
        case .appExpose: self = .appExpose
        case .showDesktop: self = .showDesktop
        case .spotlight: self = .spotlight
        case .lookUp: self = .lookUp
        case .spaceLeft: self = .spaceLeft
        case .spaceRight: self = .spaceRight
        case .launchpad: self = .launchpad
        default: return nil
        }
    }
}
