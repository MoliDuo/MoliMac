import Foundation

/// Windows-style autoscroll: after it starts, the page scrolls towards the pointer,
/// faster the further the pointer is from where it started.
public enum Autoscroll {
    /// Pixels around the start point where nothing scrolls.
    public static let deadZone = 12.0
    public static let maxSpeed = 6000.0

    /// Scroll speed in pixels per second (positive = up / left, like scroll events)
    /// for the pointer `offset` pixels from the start (positive = below / right).
    public static func velocity(offset: Double) -> Double {
        let distance = abs(offset) - deadZone
        guard distance > 0 else {
            return 0
        }
        let speed = min(2 * pow(distance, 1.4), maxSpeed)
        return offset > 0 ? -speed : speed
    }
}
