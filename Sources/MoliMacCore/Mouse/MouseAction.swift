import Foundation

/// What a remapped button does. The same action list serves clicks, holds, drags and
/// scrolls, but each action only makes sense for one of them; `kind` says which.
public enum MouseAction: Hashable, Sendable {
    case none

    // Performed once, on click or hold.
    case lookUp
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case spaceLeft
    case spaceRight
    case spotlight
    case back
    case forward
    case smartZoom
    case middleClick
    case keyboardShortcut(KeyboardShortcut)

    // Driven by mouse movement while the button is held.
    case dragSpacesAndMissionControl
    case dragScrollAndNavigate
    case dragMiddleButton

    // Driven by the scroll wheel while the button is held.
    case scrollDesktopAndLaunchpad
    case scrollZoom
    case scrollHorizontal
    case scrollSwift
    case scrollPrecise

    /// A type this version does not know, kept so saving does not erase it.
    case unknown(String)

    public enum Kind: Sendable {
        case instant
        case drag
        case scroll
    }

    public var kind: Kind {
        switch self {
        case .dragSpacesAndMissionControl, .dragScrollAndNavigate, .dragMiddleButton:
            .drag
        case .scrollDesktopAndLaunchpad, .scrollZoom, .scrollHorizontal, .scrollSwift, .scrollPrecise:
            .scroll
        default:
            .instant
        }
    }

    /// Actions offered for each kind of trigger, in menu order.
    public static func choices(for kind: TriggerKind) -> [MouseAction] {
        switch kind {
        case .click, .hold:
            [
                .lookUp, .smartZoom, .middleClick, .back, .forward,
                .missionControl, .appExpose, .showDesktop, .launchpad,
                .spaceLeft, .spaceRight, .spotlight,
            ]
        case .drag:
            [.dragSpacesAndMissionControl, .dragScrollAndNavigate, .dragMiddleButton]
        case .scroll:
            [.scrollDesktopAndLaunchpad, .scrollZoom, .scrollHorizontal, .scrollSwift, .scrollPrecise]
        }
    }

    var typeName: String {
        switch self {
        case .none: "none"
        case .lookUp: "lookUp"
        case .missionControl: "missionControl"
        case .appExpose: "appExpose"
        case .showDesktop: "showDesktop"
        case .launchpad: "launchpad"
        case .spaceLeft: "spaceLeft"
        case .spaceRight: "spaceRight"
        case .spotlight: "spotlight"
        case .back: "back"
        case .forward: "forward"
        case .smartZoom: "smartZoom"
        case .middleClick: "middleClick"
        case .keyboardShortcut: "keyboardShortcut"
        case .dragSpacesAndMissionControl: "dragSpacesAndMissionControl"
        case .dragScrollAndNavigate: "dragScrollAndNavigate"
        case .dragMiddleButton: "dragMiddleButton"
        case .scrollDesktopAndLaunchpad: "scrollDesktopAndLaunchpad"
        case .scrollZoom: "scrollZoom"
        case .scrollHorizontal: "scrollHorizontal"
        case .scrollSwift: "scrollSwift"
        case .scrollPrecise: "scrollPrecise"
        case let .unknown(name): name
        }
    }

    private static let simpleCases: [MouseAction] = [
        .none, .lookUp, .missionControl, .appExpose, .showDesktop, .launchpad,
        .spaceLeft, .spaceRight, .spotlight, .back, .forward, .smartZoom, .middleClick,
        .dragSpacesAndMissionControl, .dragScrollAndNavigate, .dragMiddleButton,
        .scrollDesktopAndLaunchpad, .scrollZoom, .scrollHorizontal, .scrollSwift, .scrollPrecise,
    ]
}

extension MouseAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case shortcut
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "keyboardShortcut" {
            self = try .keyboardShortcut(container.decode(KeyboardShortcut.self, forKey: .shortcut))
        } else if let match = Self.simpleCases.first(where: { $0.typeName == type }) {
            self = match
        } else {
            self = .unknown(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        if case let .keyboardShortcut(shortcut) = self {
            try container.encode(shortcut, forKey: .shortcut)
        }
    }
}

/// A key combination to send. Key codes are macOS virtual key codes.
public struct KeyboardShortcut: Hashable, Codable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Set<ModifierKey>

    public init(keyCode: UInt16, modifiers: Set<ModifierKey>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum ModifierKey: String, Hashable, Codable, CaseIterable, Sendable {
    case control
    case option
    case shift
    case command

    /// The order macOS prints modifiers in: ⌃⌥⇧⌘.
    public var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
}
