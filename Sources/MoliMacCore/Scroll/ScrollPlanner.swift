import Foundation

/// One notch of a mouse wheel, as the event tap sees it.
public struct WheelTick: Sendable {
    /// Positive scrolls up (or left on a horizontal wheel), like CGEvent's line delta.
    public var direction: Int
    /// The tilt wheel or a horizontal-only wheel.
    public var horizontalWheel: Bool
    /// How far macOS itself would scroll for this notch.
    public var systemPixels: Double
    /// Seconds, from any monotonic clock.
    public var time: Double
    /// Modifier keys held during the tick.
    public var held: Set<ModifierKey>

    public init(direction: Int, horizontalWheel: Bool, systemPixels: Double, time: Double, held: Set<ModifierKey>) {
        self.direction = direction
        self.horizontalWheel = horizontalWheel
        self.systemPixels = systemPixels
        self.time = time
        self.held = held
    }
}

/// What to do with one wheel tick.
public struct ScrollPlan: Equatable, Sendable {
    public enum Output: Equatable, Sendable {
        /// Send the original event on unchanged.
        case passThrough
        /// Drop the tick.
        case swallow
        /// Scroll by this many pixels (positive = up / left). A nil feel posts it at once.
        case scroll(dx: Double, dy: Double, feel: ScrollFeel?)
        /// Zoom in (positive) or out by this much magnification.
        case zoom(Double, feel: ScrollFeel?)
        case perform(MouseAction)
    }

    public var output: Output
    /// Modifier keys that picked the mode. They are removed from the posted events,
    /// so apps do not also react to them (⌃ scroll is the system zoom, for example).
    public var consumedModifiers: Set<ModifierKey>
}

/// Decides how each wheel tick scrolls: distance from the wheel speed, the mode from
/// held modifiers or the held mouse button, and the animation from the smoothness.
public struct ScrollPlanner: Sendable {
    private var acceleration = ScrollAcceleration()

    /// Magnification for one tick at the slowest and fastest wheel speed.
    public static let zoomRange = 0.04...0.16

    public init() {}

    private enum Mode {
        case normal
        case swift
        case precise
        case zoom
    }

    public mutating func plan(
        _ tick: WheelTick,
        settings: ScrollSettings,
        buttonAction: MouseAction?,
        screenHeight: Double
    ) -> ScrollPlan {
        guard tick.direction != 0 else {
            return ScrollPlan(output: .passThrough, consumedModifiers: [])
        }
        let (intensity, flings, gap) = acceleration.tick(at: tick.time)
        let sign: Double = tick.direction > 0 ? 1 : -1

        var consumed: Set<ModifierKey> = []
        func isHeld(_ key: ModifierKey?) -> Bool {
            guard let key, tick.held.contains(key) else { return false }
            consumed.insert(key)
            return true
        }

        var mode = Mode.normal
        var horizontal = tick.horizontalWheel
        switch buttonAction {
        case .scrollDesktopAndLaunchpad:
            // One action per swipe of the wheel, not per tick.
            let output: ScrollPlan.Output = gap > ScrollAcceleration.swipeGap
                ? .perform(sign > 0 ? .launchpad : .showDesktop)
                : .swallow
            return ScrollPlan(output: output, consumedModifiers: [])
        case .scrollZoom: mode = .zoom
        case .scrollHorizontal: horizontal.toggle()
        case .scrollSwift: mode = .swift
        case .scrollPrecise: mode = .precise
        default:
            let modifiers = settings.modifiers
            if isHeld(modifiers.zoom) {
                mode = .zoom
            } else if isHeld(modifiers.swift) {
                mode = .swift
            } else if isHeld(modifiers.precise) {
                mode = .precise
            }
            if mode != .zoom, isHeld(modifiers.horizontal) {
                horizontal.toggle()
            }
        }

        let smooth = ScrollFeel.smoothness(settings.smoothness)
        let pixels: Double
        let feel: ScrollFeel?
        switch mode {
        case .zoom:
            let range = Self.zoomRange
            let amount = range.lowerBound + (range.upperBound - range.lowerBound) * intensity
            return ScrollPlan(output: .zoom(sign * amount, feel: smooth), consumedModifiers: consumed)
        case .swift:
            pixels = ScrollAcceleration.swiftPixels(screenHeight: screenHeight, intensity: intensity)
            feel = .swift
        case .precise:
            pixels = ScrollAcceleration.precisePixels(intensity: intensity)
            feel = smooth == nil ? nil : .precise
        case .normal:
            if settings.precision, gap > ScrollAcceleration.precisionGap {
                pixels = ScrollAcceleration.precisionTick
                feel = smooth == nil ? nil : .precise
            } else if let range = ScrollAcceleration.range(for: settings.speed) {
                pixels = ScrollAcceleration.pixels(range: range, intensity: intensity, flings: flings)
                feel = smooth
            } else {
                // Nothing to change: leave the event alone.
                let untouched = smooth == nil && !settings.reverse && !settings.trackpadSimulation
                    && horizontal == tick.horizontalWheel && consumed.isEmpty
                if untouched {
                    return ScrollPlan(output: .passThrough, consumedModifiers: [])
                }
                pixels = max(tick.systemPixels, 1)
                feel = smooth
            }
        }

        let distance = sign * pixels * (settings.reverse ? -1 : 1)
        let output: ScrollPlan.Output = horizontal
            ? .scroll(dx: distance, dy: 0, feel: feel)
            : .scroll(dx: 0, dy: distance, feel: feel)
        return ScrollPlan(output: output, consumedModifiers: consumed)
    }
}
