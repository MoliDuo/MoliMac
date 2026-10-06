import Foundation

/// Turns presses, releases, movement and wheel ticks of remapped buttons into
/// gestures: click, double click, hold, drag and scroll.
///
/// It owns no timers and reads no clock. Each press asks the caller to start two
/// timers (`scheduleTimers`) and the caller reports them back with the token it was
/// given, so tests drive every timing case without waiting.
public struct ClickCycle: Sendable {
    public struct Timing: Sendable {
        /// Holding longer than this is a hold.
        public var hold: Double = 0.25
        /// A press within this long after the previous press continues the click cycle.
        public var clickLevel: Double = 0.26
        /// Moving further than this many pixels while pressed is a drag.
        public var dragThreshold: Double = 7

        public init() {}
    }

    public enum Effect: Equatable, Sendable {
        case perform(MouseAction)
        case beginDrag(MouseAction)
        case endDrag
        case beginScroll(MouseAction)
        case endScroll
        /// The user clicked but nothing is mapped to that: send the clicks on unchanged.
        case replayClick(button: Int, count: Int)
        /// The user dragged but nothing is mapped to that: send the press on now and let
        /// the rest of the drag through, so dragging with the button still works in apps.
        case replayPress(button: Int)
        /// Start the hold timer (`timing.hold`) and the click-level timer (`timing.clickLevel`).
        case scheduleTimers(token: Int)
    }

    private enum Phase: Sendable {
        case idle
        case down
        case waitingForNextClick
        case held
        case dragging
        case scrolling(MouseAction)
        case passthrough
    }

    public var table: RemapTable
    public let timing: Timing

    private var button: Int?
    private var clicks = 0
    private var phase = Phase.idle
    private var token = 0
    /// Whether a new press would still count as the next click of this cycle.
    private var levelOpen = false
    private var travelX = 0.0
    private var travelY = 0.0

    public init(table: RemapTable, timing: Timing = Timing()) {
        self.table = table
        self.timing = timing
    }

    public var isIdle: Bool {
        if case .idle = phase {
            return true
        }
        return false
    }

    public var isDragging: Bool {
        if case .dragging = phase {
            return true
        }
        return false
    }

    public var activeButton: Int? {
        button
    }

    // MARK: - Inputs

    public mutating func press(button pressed: Int) -> [Effect] {
        var effects: [Effect] = []
        let continues: Bool
        if button == pressed, case .waitingForNextClick = phase, levelOpen {
            continues = true
        } else {
            effects += finish()
            continues = false
        }

        clicks = continues ? min(clicks + 1, Trigger.maxClicks) : 1
        button = pressed
        phase = .down
        levelOpen = true
        travelX = 0
        travelY = 0
        token += 1
        effects.append(.scheduleTimers(token: token))
        return effects
    }

    /// - Returns: the effects, and whether the release itself should go on to the system.
    public mutating func release(button released: Int) -> (effects: [Effect], passThrough: Bool) {
        guard released == button else {
            // A release we never saw the press of (for example from before the app started).
            return ([], true)
        }

        switch phase {
        case .dragging:
            reset()
            return ([.endDrag], false)
        case .scrolling:
            reset()
            return ([.endScroll], false)
        case .held:
            reset()
            return ([], false)
        case .passthrough:
            reset()
            return ([], true)
        case .down:
            if levelOpen, table.hasMappings(button: released, beyond: clicks) {
                phase = .waitingForNextClick
                return ([], false)
            }
            let effects = clickEffects(button: released)
            reset()
            return (effects, false)
        case .idle, .waitingForNextClick:
            return ([], false)
        }
    }

    public mutating func holdTimerFired(token fired: Int) -> [Effect] {
        guard fired == token, case .down = phase, let button else {
            return []
        }
        guard let action = table.action(button: button, clicks: clicks, kind: .hold) else {
            return []
        }
        phase = .held
        return [.perform(action)]
    }

    public mutating func levelTimerFired(token fired: Int) -> [Effect] {
        guard fired == token else {
            return []
        }
        levelOpen = false
        guard case .waitingForNextClick = phase, let button else {
            return []
        }
        let effects = clickEffects(button: button)
        reset()
        return effects
    }

    /// - Returns: the effects, and whether the movement belongs to a drag gesture (the
    ///   caller then keeps the pointer still and feeds the movement to the drag output).
    public mutating func move(dx: Double, dy: Double) -> (effects: [Effect], consumed: Bool) {
        switch phase {
        case .dragging:
            return ([], true)
        case .down:
            travelX += dx
            travelY += dy
            guard max(abs(travelX), abs(travelY)) >= timing.dragThreshold, let button else {
                return ([], false)
            }
            if let action = table.action(button: button, clicks: clicks, kind: .drag) {
                phase = .dragging
                return ([.beginDrag(action)], true)
            }
            phase = .passthrough
            return ([.replayPress(button: button)], false)
        default:
            return ([], false)
        }
    }

    /// - Returns: the effects, and the scroll action the wheel tick belongs to, or nil
    ///   when the tick is an ordinary scroll.
    public mutating func scroll() -> (effects: [Effect], action: MouseAction?) {
        switch phase {
        case let .scrolling(action):
            return ([], action)
        case .down:
            guard let button, let action = table.action(button: button, clicks: clicks, kind: .scroll) else {
                return ([], nil)
            }
            phase = .scrolling(action)
            return ([.beginScroll(action)], action)
        default:
            return ([], nil)
        }
    }

    /// Ends whatever is in progress, for example when the module is paused.
    public mutating func cancel() -> [Effect] {
        finish()
    }

    // MARK: - Helpers

    private func clickEffects(button: Int) -> [Effect] {
        if let action = table.action(button: button, clicks: clicks, kind: .click) {
            return [.perform(action)]
        }
        return [.replayClick(button: button, count: clicks)]
    }

    /// Closes the current cycle before another one starts.
    private mutating func finish() -> [Effect] {
        var effects: [Effect] = []
        switch phase {
        case .dragging:
            effects = [.endDrag]
        case .scrolling:
            effects = [.endScroll]
        case .waitingForNextClick:
            if let button {
                effects = clickEffects(button: button)
            }
        case .idle, .down, .held, .passthrough:
            break
        }
        reset()
        return effects
    }

    private mutating func reset() {
        button = nil
        clicks = 0
        phase = .idle
        levelOpen = false
        travelX = 0
        travelY = 0
    }
}
