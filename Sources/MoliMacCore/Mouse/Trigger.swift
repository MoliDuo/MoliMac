import Foundation

/// How a button is used. Every kind can follow one or more quick clicks, so
/// "double click and drag" is `Trigger(button:, clicks: 2, kind: .drag)`.
public enum TriggerKind: String, Hashable, Codable, CaseIterable, Sendable {
    case click
    case hold
    case drag
    case scroll

    public var actionKind: MouseAction.Kind {
        switch self {
        case .click, .hold: .instant
        case .drag: .drag
        case .scroll: .scroll
        }
    }
}

/// Buttons are numbered the way people count them: 1 left, 2 right, 3 middle,
/// 4 and 5 the side buttons. CGEvent counts from 0; the app layer converts.
public struct Trigger: Hashable, Codable, Sendable {
    public static let maxClicks = 3

    public var button: Int
    public var clicks: Int
    public var kind: TriggerKind

    public init(button: Int, clicks: Int = 1, kind: TriggerKind) {
        self.button = button
        self.clicks = clicks
        self.kind = kind
    }
}

public struct ButtonMapping: Hashable, Codable, Sendable {
    public var trigger: Trigger
    public var action: MouseAction

    public init(_ trigger: Trigger, _ action: MouseAction) {
        self.trigger = trigger
        self.action = action
    }
}

/// Lookup over the user's mappings. Left and right buttons are never remapped:
/// taking them over would make a mistake in the settings lock the user out.
public struct RemapTable: Sendable {
    public static let remappableButtons = 3...32

    private var actions: [Trigger: MouseAction] = [:]
    private var buttons: Set<Int> = []

    public init(_ mappings: [ButtonMapping]) {
        for mapping in mappings where Self.remappableButtons.contains(mapping.trigger.button) {
            guard (1...Trigger.maxClicks).contains(mapping.trigger.clicks) else {
                continue
            }
            guard mapping.action != .none, mapping.action.kind == mapping.trigger.kind.actionKind else {
                continue
            }
            if case .unknown = mapping.action {
                continue
            }
            // The first mapping for a trigger wins, matching the order shown in the settings.
            if actions[mapping.trigger] == nil {
                actions[mapping.trigger] = mapping.action
                buttons.insert(mapping.trigger.button)
            }
        }
    }

    public var isEmpty: Bool {
        actions.isEmpty
    }

    public func isRemapped(button: Int) -> Bool {
        buttons.contains(button)
    }

    public func action(button: Int, clicks: Int, kind: TriggerKind) -> MouseAction? {
        actions[Trigger(button: button, clicks: clicks, kind: kind)]
    }

    /// True when anything is mapped to a later click of the same cycle, so a click at
    /// `clicks` has to wait and see whether the user clicks again.
    public func hasMappings(button: Int, beyond clicks: Int) -> Bool {
        actions.keys.contains { $0.button == button && $0.clicks > clicks }
    }

    /// True when holding after `clicks` quick clicks does something (hold, drag or scroll).
    public func usesPress(button: Int, clicks: Int) -> Bool {
        actions.keys.contains { $0.button == button && $0.clicks == clicks && $0.kind != .click }
    }
}
