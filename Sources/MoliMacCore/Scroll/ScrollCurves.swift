import Foundation

/// Motion that slows down under drag: dv/dt = -c * v^e, until the speed drops below `stopSpeed`.
/// Closed forms (e != 1):
///   v(t) = (v0^(1-e) - (1-e) c t)^(1/(1-e))
///   s(t) = (v0^(2-e) - v(t)^(2-e)) / ((2-e) c)
public struct DragCurve: Equatable, Sendable {
    public var coefficient: Double
    public var exponent: Double
    /// Pixels per second below which the motion stops.
    public var stopSpeed: Double

    public init(coefficient: Double, exponent: Double, stopSpeed: Double) {
        precondition(exponent < 1, "exponent must stay below 1 for the closed forms")
        self.coefficient = coefficient
        self.exponent = exponent
        self.stopSpeed = stopSpeed
    }

    public func duration(from v0: Double) -> Double {
        guard v0 > stopSpeed else { return 0 }
        let k = 1 - exponent
        return (pow(v0, k) - pow(stopSpeed, k)) / (k * coefficient)
    }

    public func distance(from v0: Double) -> Double {
        guard v0 > stopSpeed else { return 0 }
        let m = 2 - exponent
        return (pow(v0, m) - pow(stopSpeed, m)) / (m * coefficient)
    }

    public func velocity(at t: Double, from v0: Double) -> Double {
        let k = 1 - exponent
        let base = pow(v0, k) - k * coefficient * t
        return base > 0 ? pow(base, 1 / k) : 0
    }

    public func position(at t: Double, from v0: Double) -> Double {
        let end = duration(from: v0)
        guard end > 0 else { return 0 }
        let clamped = min(max(t, 0), end)
        let m = 2 - exponent
        return (pow(v0, m) - pow(velocity(at: clamped, from: v0), m)) / (m * coefficient)
    }
}

/// One scroll animation: an eased base segment of fixed duration, then a drag tail
/// that starts at the base's final speed. The base distance is chosen so that base
/// plus tail cover exactly `distance`.
///
/// The base is a blend of linear and ease-out, B(u) = (1-a)u + a(2u-u²), so it
/// starts fast and still moves at the end, handing a non-zero speed to the tail.
public struct HybridCurve: Equatable, Sendable {
    public let distance: Double
    public let baseDuration: Double
    public let easing: Double
    public let drag: DragCurve?

    public private(set) var baseDistance: Double
    /// Speed at the end of the base, which is where the tail starts.
    public private(set) var handoverSpeed: Double
    public private(set) var duration: Double

    public init(distance: Double, baseDuration: Double, easing: Double = 0.5, drag: DragCurve?) {
        self.distance = abs(distance)
        self.baseDuration = baseDuration
        self.easing = easing
        self.drag = drag
        baseDistance = self.distance
        handoverSpeed = 0
        duration = baseDuration

        let endSlope = 1 - easing
        guard let drag, self.distance > 0, endSlope > 0 else { return }

        let total = self.distance
        func overshoot(_ base: Double) -> Double {
            base + drag.distance(from: base * endSlope / baseDuration) - total
        }
        // Base plus tail grows with the base distance, so bisect.
        var low = 0.0
        var high = total
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if overshoot(mid) > 0 {
                high = mid
            } else {
                low = mid
            }
        }
        baseDistance = high
        handoverSpeed = baseDistance * endSlope / baseDuration
        duration = baseDuration + drag.duration(from: handoverSpeed)
    }

    /// Distance covered after `t` seconds, from 0 to `distance`.
    public func position(at t: Double) -> Double {
        guard t > 0 else { return 0 }
        if t < baseDuration {
            let u = t / baseDuration
            return baseDistance * ((1 - easing) * u + easing * (2 * u - u * u))
        }
        guard let drag else { return distance }
        let tail = drag.position(at: t - baseDuration, from: handoverSpeed)
        return t >= duration ? distance : min(baseDistance + tail, distance)
    }

    /// Whether `t` falls in the tail, which trackpad simulation reports as momentum.
    public func isMomentum(at t: Double) -> Bool {
        drag != nil && t >= baseDuration && t < duration
    }
}

/// Animation timing for each kind of scroll.
public struct ScrollFeel: Equatable, Sendable {
    public var baseDuration: Double
    public var easing: Double
    public var drag: DragCurve?

    public static func smoothness(_ smoothness: Smoothness) -> ScrollFeel? {
        switch smoothness {
        case .off:
            nil
        case .low:
            ScrollFeel(baseDuration: 0.09, easing: 0.8, drag: nil)
        case .regular:
            ScrollFeel(baseDuration: 0.14, easing: 0.5, drag: DragCurve(coefficient: 60, exponent: 0.7, stopSpeed: 50))
        case .high:
            ScrollFeel(baseDuration: 0.22, easing: 0.5, drag: DragCurve(coefficient: 40, exponent: 0.7, stopSpeed: 30))
        }
    }

    public static let precise = ScrollFeel(baseDuration: 0.14, easing: 0.8, drag: nil)
    public static let swift = ScrollFeel(
        baseDuration: 0.30,
        easing: 0.5,
        drag: DragCurve(coefficient: 30, exponent: 0.7, stopSpeed: 50)
    )
}
