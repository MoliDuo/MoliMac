import Foundation

/// Plays wheel ticks out as smooth motion along one axis.
///
/// Each tick restarts the animation from where it is now, covering what was left of
/// the previous one plus the new tick's distance. A tick in the opposite direction
/// drops what was left, so reversing feels immediate. Time is passed in by the caller.
public struct ScrollAnimator: Sendable {
    public enum Phase: Equatable, Sendable {
        /// Driven by the wheel, like fingers on a trackpad.
        case gesture
        /// The drag tail after the wheel stopped, like trackpad momentum.
        case momentum
    }

    public struct Frame: Equatable, Sendable {
        public var delta: Double
        public var phase: Phase
        public var finished: Bool
    }

    private var curve: HybridCurve?
    private var sign = 1.0
    private var start = 0.0
    private var emitted = 0.0

    public init() {}

    public var isRunning: Bool {
        curve != nil
    }

    public mutating func add(distance: Double, feel: ScrollFeel, now: Double) {
        guard distance != 0 else { return }
        let newSign: Double = distance > 0 ? 1 : -1
        var remaining = 0.0
        if let curve, newSign == sign {
            remaining = curve.distance - curve.position(at: now - start)
        }
        sign = newSign
        start = now
        emitted = 0
        curve = HybridCurve(
            distance: remaining + abs(distance),
            baseDuration: feel.baseDuration,
            easing: feel.easing,
            drag: feel.drag
        )
    }

    /// Advances to `now` and returns the movement since the last frame.
    public mutating func frame(now: Double) -> Frame? {
        guard let curve else { return nil }
        let t = now - start
        let position = curve.position(at: t)
        let delta = (position - emitted) * sign
        emitted = position
        let finished = t >= curve.duration
        let phase: Phase = curve.isMomentum(at: t) ? .momentum : .gesture
        if finished {
            self.curve = nil
        }
        return Frame(delta: delta, phase: phase, finished: finished)
    }

    public mutating func stop() {
        curve = nil
    }
}

/// Turns fractional pixel deltas into whole pixels without losing the remainder,
/// so many small frames add up to the right distance.
public struct SubpixelAccumulator: Sendable {
    private var remainder = 0.0

    public init() {}

    public mutating func take(_ delta: Double) -> Int {
        let total = remainder + delta
        let whole = total.rounded(.towardZero)
        remainder = total - whole
        return Int(whole)
    }

    public mutating func reset() {
        remainder = 0
    }
}
