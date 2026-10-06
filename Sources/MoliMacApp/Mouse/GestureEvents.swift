import CoreGraphics
import MoliMacCore

/// Trackpad gesture events, built from CGEvent fields that are not in the public
/// headers. The numbers come from watching real trackpad events (as documented by
/// Mac Mouse Fix); if Apple changes them, the gestures stop working but nothing else.
enum GestureEvents {
    /// `NSEventTypeGesture`, the companion event every trackpad gesture comes with.
    static let gestureType = CGEventType(rawValue: 29)!

    enum Field {
        static let subtype = CGEventField(rawValue: 110)!
        static let magnification = CGEventField(rawValue: 113)!
        static let swipeDirection = CGEventField(rawValue: 115)!
        static let swipeMotion = CGEventField(rawValue: 124)!
        static let phase = CGEventField(rawValue: 132)!
    }

    /// IOHIDEventType values used as gesture subtypes.
    enum Subtype: Int64 {
        case scroll = 6
        case zoom = 8
        case navigationSwipe = 16
        case smartZoom = 22
    }

    /// IOHIDEventPhase values, also used by scroll events' `scrollPhase`.
    enum Phase: Int64 {
        case none = 0
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
        case mayBegin = 128
    }

    /// Scroll events' `momentumPhase`.
    enum MomentumPhase: Int64 {
        case none = 0
        case begin = 1
        case `continue` = 2
        case end = 3
    }

    static func makeGesture(_ subtype: Subtype, phase: Phase) -> CGEvent? {
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        event.type = gestureType
        event.location = CGEvent(source: nil)?.location ?? .zero
        event.setIntegerValueField(Field.subtype, value: subtype.rawValue)
        event.setIntegerValueField(Field.phase, value: phase.rawValue)
        return event
    }

    static func post(_ event: CGEvent, flags: CGEventFlags) {
        event.flags = flags
        SyntheticEvents.mark(event)
        event.post(tap: .cgSessionEventTap)
    }

    // MARK: - Scrolling

    /// A pixel scroll event. With a phase it looks like two fingers on a trackpad
    /// (rubber-banding, swipe navigation); without one it is a plain smooth scroll.
    static func postScroll(
        dx: Int,
        dy: Int,
        phase: Phase,
        momentum: MomentumPhase,
        flags: CGEventFlags
    ) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(clamping: dy),
            wheel2: Int32(clamping: dx),
            wheel3: 0
        ) else {
            return
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum.rawValue)
        if phase != .none, let gesture = makeGesture(.scroll, phase: phase) {
            post(gesture, flags: flags)
        }
        post(event, flags: flags)
    }

    // MARK: - Zoom

    static func postZoom(phase: Phase, magnification: Double, flags: CGEventFlags) {
        guard let event = makeGesture(.zoom, phase: phase) else {
            return
        }
        event.setDoubleValueField(Field.magnification, value: magnification)
        post(event, flags: flags)
    }

    static func postSmartZoom() {
        guard let event = makeGesture(.smartZoom, phase: .none) else {
            return
        }
        post(event, flags: SyntheticEvents.currentFlags)
    }

    // MARK: - Navigation

    /// A three-finger swipe, which Apple's apps take as back or forward.
    static func postNavigationSwipe(back: Bool) {
        // IOHIDSwipeMask: left 4, right 8. The motion field holds ±1 as raw float bits.
        let direction: Int64 = back ? 4 : 8
        let motion = Double(Float(bitPattern: back ? 0x0000_0001 : 0x8000_0001))
        for phase in [Phase.began, .ended] {
            guard let event = makeGesture(.navigationSwipe, phase: phase) else {
                return
            }
            event.setIntegerValueField(Field.swipeDirection, value: direction)
            event.setDoubleValueField(Field.swipeMotion, value: motion)
            post(event, flags: SyntheticEvents.currentFlags)
        }
    }
}
