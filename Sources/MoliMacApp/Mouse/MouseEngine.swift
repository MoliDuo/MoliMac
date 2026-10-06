import CoreGraphics
import Foundation
import MoliMacCore

/// The event tap that takes over remapped mouse buttons.
///
/// Everything here runs on `EventTapThread`, including the tap callback and the
/// click cycle timers, so the state needs no locks. Other threads call in with
/// `thread.perform`.
final class MouseEngine: @unchecked Sendable {
    /// What the main thread hands over whenever settings, permission or sleep change.
    struct Configuration: Sendable {
        var table = RemapTable([])
        var scroll = ScrollSettings()
        var screenHeight = 1000.0
        var active = false
    }

    private let thread: EventTapThread
    private let scroll: ScrollEngine
    private var cycle = ClickCycle(table: RemapTable([]))
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    /// While the settings page captures a button, every event goes through untouched.
    private var bypass = false

    init(thread: EventTapThread, clock: FrameClock) {
        self.thread = thread
        scroll = ScrollEngine(clock: clock)
    }

    // MARK: - Control (on the tap thread)

    /// Installs or removes the tap. Removing it first ends a gesture in progress.
    func configure(_ configuration: Configuration) {
        cycle.table = configuration.table
        scroll.settings = configuration.scroll
        scroll.screenHeight = configuration.screenHeight
        if configuration.active {
            installTap()
        } else {
            removeTap()
        }
    }

    func setBypass(_ bypass: Bool) {
        self.bypass = bypass
        if bypass {
            apply(cycle.cancel())
        }
    }

    private func installTap() {
        guard tap == nil, let runLoop = thread.runLoop else {
            return
        }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseEngineTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.mouse.error("could not create the mouse event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        self.tap = tap
        tapSource = source
        Log.mouse.info("mouse event tap on")
    }

    private func removeTap() {
        apply(cycle.cancel())
        scroll.cancel()
        guard let tap else {
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource, let runLoop = thread.runLoop {
            CFRunLoopRemoveSource(runLoop, tapSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
        Log.mouse.info("mouse event tap off")
    }

    // MARK: - Events

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system turns a tap off when a callback is slow or secure input
            // starts; turn it straight back on.
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            Log.mouse.info("mouse event tap re-enabled after type \(type.rawValue)")
            return pass
        }
        if bypass || SyntheticEvents.isSynthetic(event) {
            return pass
        }
        let swallow: Bool = switch type {
        case .otherMouseDown: buttonDown(event)
        case .otherMouseUp: buttonUp(event)
        case .otherMouseDragged: dragged(event)
        case .scrollWheel: scrolled(event)
        default: false
        }
        return swallow ? nil : pass
    }

    private static func button(of event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
    }

    private func buttonDown(_ event: CGEvent) -> Bool {
        let button = Self.button(of: event)
        guard cycle.table.isRemapped(button: button) else {
            return false
        }
        apply(cycle.press(button: button))
        return true
    }

    private func buttonUp(_ event: CGEvent) -> Bool {
        let (effects, passThrough) = cycle.release(button: Self.button(of: event))
        apply(effects)
        return !passThrough
    }

    private func dragged(_ event: CGEvent) -> Bool {
        guard cycle.activeButton == Self.button(of: event) else {
            return false
        }
        let (effects, _) = cycle.move(
            dx: event.getDoubleValueField(.mouseEventDeltaX),
            dy: event.getDoubleValueField(.mouseEventDeltaY)
        )
        apply(effects)
        // Drag actions are not implemented yet, so the pointer keeps moving.
        return false
    }

    private func scrolled(_ event: CGEvent) -> Bool {
        var buttonAction: MouseAction?
        if !cycle.isIdle {
            let (effects, action) = cycle.scroll()
            apply(effects)
            buttonAction = action
        }
        return scroll.handle(event, buttonAction: buttonAction)
    }

    // MARK: - Effects

    private func apply(_ effects: [ClickCycle.Effect]) {
        for effect in effects {
            switch effect {
            case let .perform(action):
                ActionPerformer.perform(action)
            case let .replayClick(button, count):
                SyntheticEvents.postClicks(button: button, count: count)
            case let .replayPress(button):
                SyntheticEvents.postMouse(button: button, down: true)
            case let .scheduleTimers(token):
                scheduleTimers(token: token)
            case let .beginDrag(action):
                Log.mouse.info("\(String(describing: action), privacy: .public) is not available yet")
            case .beginScroll, .endScroll, .endDrag:
                // Wheel ticks during a button scroll go to the scroll engine as they come.
                break
            }
        }
    }

    private func scheduleTimers(token: Int) {
        thread.perform(after: cycle.timing.hold) { [self] in
            apply(cycle.holdTimerFired(token: token))
        }
        thread.perform(after: cycle.timing.clickLevel) { [self] in
            apply(cycle.levelTimerFired(token: token))
        }
    }
}

private func mouseEngineTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    return Unmanaged<MouseEngine>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
