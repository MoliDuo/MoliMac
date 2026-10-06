import Foundation

/// The edits the button settings page makes to the list of mappings.
///
/// The page shows one group per button, rows sorted by trigger. Rows the user has
/// added but not given an action yet are stored with `.none`, which `RemapTable`
/// ignores, so a half-made row never changes what the mouse does.
public enum ButtonList {
    /// Buttons that have rows, in ascending order.
    public static func buttons(in mappings: [ButtonMapping]) -> [Int] {
        Array(Set(mappings.map(\.trigger.button))).sorted()
    }

    /// The rows for `button`, sorted by trigger.
    public static func mappings(for button: Int, in mappings: [ButtonMapping]) -> [ButtonMapping] {
        mappings.filter { $0.trigger.button == button }.sorted { $0.trigger < $1.trigger }
    }

    /// Triggers that `button` has no row for yet, in menu order.
    public static func unusedTriggers(for button: Int, in mappings: [ButtonMapping]) -> [Trigger] {
        let used = Set(mappings.map(\.trigger))
        return (1...Trigger.maxClicks).flatMap { clicks in
            TriggerKind.allCases.map { Trigger(button: button, clicks: clicks, kind: $0) }
        }
        .filter { !used.contains($0) }
    }

    /// Adds an empty click row for a button the user just pressed in the capture area.
    /// - Returns: false when the button cannot be remapped or already has rows.
    @discardableResult
    public static func addButton(_ button: Int, to mappings: inout [ButtonMapping]) -> Bool {
        guard RemapTable.remappableButtons.contains(button),
              !mappings.contains(where: { $0.trigger.button == button })
        else {
            return false
        }
        mappings.append(ButtonMapping(Trigger(button: button, kind: .click), .none))
        return true
    }

    /// Adds an empty row for `trigger` unless one exists.
    public static func add(_ trigger: Trigger, to mappings: inout [ButtonMapping]) {
        guard !mappings.contains(where: { $0.trigger == trigger }) else {
            return
        }
        mappings.append(ButtonMapping(trigger, .none))
    }

    /// Sets the action of every row for `trigger`; duplicates left by hand edits stay in step.
    public static func setAction(_ action: MouseAction, for trigger: Trigger, in mappings: inout [ButtonMapping]) {
        for index in mappings.indices where mappings[index].trigger == trigger {
            mappings[index].action = action
        }
    }

    public static func remove(_ trigger: Trigger, from mappings: inout [ButtonMapping]) {
        mappings.removeAll { $0.trigger == trigger }
    }
}

extension Trigger: Comparable {
    /// Button, then number of clicks, then click, hold, drag, scroll.
    public static func < (lhs: Trigger, rhs: Trigger) -> Bool {
        (lhs.button, lhs.clicks, lhs.kind.order) < (rhs.button, rhs.clicks, rhs.kind.order)
    }
}

private extension TriggerKind {
    var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
