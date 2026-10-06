import Foundation

public enum DragAxis: Sendable {
    case horizontal
    case vertical
}

/// "Spaces and Mission Control" while a button is held and the mouse moves: sideways
/// switches desktops, up opens Mission Control, down shows the app's windows.
///
/// The direction locks once the mouse has moved `threshold` pixels. Sideways keeps
/// going: every further `step` pixels switches one more desktop, in either direction.
public struct SpacesDrag: Sendable {
    public static let threshold = 60.0
    public static let step = 180.0

    private var x = 0.0
    private var y = 0.0
    private var axis: DragAxis?
    /// Horizontal position of the last switch.
    private var anchor = 0.0

    public init() {}

    public mutating func move(dx: Double, dy: Double) -> [MouseAction] {
        x += dx
        y += dy
        switch axis {
        case nil:
            guard max(abs(x), abs(y)) >= Self.threshold else {
                return []
            }
            if abs(x) >= abs(y) {
                axis = .horizontal
                anchor = x
                return [Self.space(movingRight: x > 0)]
            }
            axis = .vertical
            // Screen coordinates grow downwards, so moving up is negative.
            return [y < 0 ? .missionControl : .appExpose]
        case .horizontal:
            var actions: [MouseAction] = []
            while abs(x - anchor) >= Self.step {
                let right = x > anchor
                anchor += right ? Self.step : -Self.step
                actions.append(Self.space(movingRight: right))
            }
            return actions
        case .vertical:
            return []
        }
    }

    /// The desktop follows the pointer like a page: pulling it right reveals the one on the left.
    private static func space(movingRight: Bool) -> MouseAction {
        movingRight ? .spaceLeft : .spaceRight
    }
}

/// "Scroll and navigate" while a button is held: the content follows the mouse, on
/// one axis picked at the start, and keeps gliding after the button is released.
public struct DragScroll: Sendable {
    /// Movement before the axis locks.
    public static let lockDistance = 4.0
    /// Mouse pixels to content pixels.
    public static let gain = 1.5
    /// Releasing longer than this after the last movement means the mouse had stopped.
    public static let stillGap = 0.06
    /// The glide after release, like trackpad momentum.
    public static let momentum = DragCurve(coefficient: 30, exponent: 0.7, stopSpeed: 1)

    public private(set) var axis: DragAxis?
    private var pendingX = 0.0
    private var pendingY = 0.0
    private var velocity = 0.0
    private var lastTime: Double?

    public init() {}

    /// - Returns: the scroll deltas to post, positive meaning up / left like scroll events.
    public mutating func move(dx: Double, dy: Double, time: Double) -> (dx: Double, dy: Double) {
        if axis == nil {
            pendingX += dx
            pendingY += dy
            guard max(abs(pendingX), abs(pendingY)) >= Self.lockDistance else {
                return (0, 0)
            }
            axis = abs(pendingX) >= abs(pendingY) ? .horizontal : .vertical
            return output(axis == .horizontal ? pendingX : pendingY, time: time)
        }
        return output(axis == .horizontal ? dx : dy, time: time)
    }

    /// Pixels per second along the locked axis at release; zero if the mouse had stopped.
    public func releaseVelocity(at time: Double) -> Double {
        guard let lastTime, time - lastTime <= Self.stillGap else {
            return 0
        }
        return velocity
    }

    private mutating func output(_ movement: Double, time: Double) -> (dx: Double, dy: Double) {
        // Pulling the mouse down drags the content down, which is scrolling up (positive).
        let delta = movement * Self.gain
        if let lastTime, time > lastTime {
            let instant = delta / (time - lastTime)
            velocity = 0.6 * instant + 0.4 * velocity
        }
        lastTime = time
        return axis == .horizontal ? (delta, 0) : (0, delta)
    }
}

/// Plays out a glide with a drag curve, frame by frame.
public struct MomentumAnimator: Sendable {
    private var curve: DragCurve?
    private var speed = 0.0
    private var sign = 1.0
    private var start = 0.0
    private var emitted = 0.0

    public init() {}

    public var isRunning: Bool {
        curve != nil
    }

    public mutating func start(velocity: Double, curve: DragCurve, now: Double) {
        guard abs(velocity) > curve.stopSpeed else {
            stop()
            return
        }
        self.curve = curve
        speed = abs(velocity)
        sign = velocity > 0 ? 1 : -1
        start = now
        emitted = 0
    }

    /// The movement since the last frame, and whether the glide is over.
    public mutating func frame(now: Double) -> (delta: Double, finished: Bool)? {
        guard let curve else { return nil }
        let t = now - start
        let finished = t >= curve.duration(from: speed)
        // Never step backwards from rounding, and land exactly on the end.
        let position = finished ? curve.distance(from: speed) : max(curve.position(at: t, from: speed), emitted)
        let delta = (position - emitted) * sign
        emitted = position
        if finished {
            self.curve = nil
        }
        return (delta, finished)
    }

    public mutating func stop() {
        curve = nil
    }
}
