import Foundation

/// Decides how far one wheel tick scrolls, from how fast the wheel is turning.
public struct ScrollAcceleration: Sendable {
    /// Ticks further apart than this start a new swipe.
    public static let swipeGap = 0.16
    /// Ticks this close together are the fastest the curve distinguishes.
    public static let fastestGap = 0.015
    /// A new swipe this soon after the last one counts as continuing to fling.
    public static let flingGap = 0.6
    /// Turning slower than this (seconds between ticks) is slow enough for precision mode.
    public static let precisionGap = 0.12

    /// Pixels per tick at the slowest and fastest wheel speed.
    public static func range(for speed: ScrollSpeed) -> ClosedRange<Double>? {
        switch speed {
        case .system: nil
        case .low: 30...90
        case .medium: 60...120
        case .high: 120...180
        }
    }

    public static let preciseRange = 3.0...20.0
    public static let precisionTick = 12.0

    private var lastTick: Double?
    private var smoothedRate = 0.0
    private var trend = 0.0
    private var swipeTicks = 0
    private var lastSwipeTicks = 0
    private var flings = 0

    public init() {}

    /// Registers a tick and returns how fast the wheel is turning, from 0 (slow) to 1 (fast),
    /// and how many quick swipes in a row the user has made.
    public mutating func tick(at now: Double) -> (intensity: Double, flings: Int, gap: Double) {
        let gap = lastTick.map { now - $0 } ?? .infinity
        lastTick = now

        if gap > Self.swipeGap {
            // A new swipe. It continues a fling when the last swipe was a real one and recent.
            if gap < Self.flingGap, lastSwipeTicks + swipeTicks >= 3 {
                flings += 1
            } else {
                flings = 0
            }
            lastSwipeTicks = swipeTicks
            swipeTicks = 1
            smoothedRate = 1 / Self.swipeGap
            trend = 0
            return (0, flings, gap)
        }

        swipeTicks += 1
        // Double exponential smoothing keeps one uneven tick from jolting the speed.
        let rate = 1 / max(gap, Self.fastestGap)
        let previous = smoothedRate
        smoothedRate = 0.5 * rate + 0.5 * (smoothedRate + trend)
        trend = 0.2 * (smoothedRate - previous) + 0.8 * trend

        let slowest = 1 / Self.swipeGap
        let fastest = 1 / Self.fastestGap
        let t = min(max((smoothedRate - slowest) / (fastest - slowest), 0), 1)
        return (t, flings, gap)
    }

    /// Pixels for one tick in normal scrolling.
    public static func pixels(range: ClosedRange<Double>, intensity: Double, flings: Int) -> Double {
        let base = range.lowerBound + (range.upperBound - range.lowerBound) * intensity
        // Flinging again and again speeds up, like on a trackpad, up to 4x.
        let boost = flings >= 1 ? min(1 + 0.5 * Double(flings), 4) : 1
        return base * boost
    }

    /// Pixels for one tick with the "swift" modifier: most of a screen.
    public static func swiftPixels(screenHeight: Double, intensity: Double) -> Double {
        screenHeight * (0.5 + intensity)
    }

    public static func precisePixels(intensity: Double) -> Double {
        preciseRange.lowerBound + (preciseRange.upperBound - preciseRange.lowerBound) * intensity
    }
}
