import CoreGraphics
import MoliMacCore
import QuartzCore

/// Smooth scrolling for mouse wheels. Runs on the event tap thread.
///
/// Each wheel tick goes through `ScrollPlanner`, which decides the distance and the
/// mode; the animators play it out frame by frame and the outputs post the events.
/// Trackpads, Magic Mice and tablets already scroll smoothly and are left alone.
final class ScrollEngine {
    var settings = ScrollSettings() {
        didSet {
            output.simulatesTrackpad = settings.trackpadSimulation
        }
    }

    var screenHeight = 1000.0

    private let clock: FrameClock
    private var planner = ScrollPlanner()
    private var animator = ScrollAnimator()
    private var animatingHorizontally = false
    private var zoomAnimator = ScrollAnimator()
    private var momentum = MomentumAnimator()
    private var momentumHorizontally = false
    private let output = ScrollOutput()
    private let zoom = ZoomOutput()

    /// Zoom amounts are animated as if they were pixels, scaled by this.
    private static let zoomScale = 1000.0

    init(clock: FrameClock) {
        self.clock = clock
        clock.onFrame = { [weak self] now in
            self?.frame(now: now)
        }
    }

    /// - Returns: true when the event was handled and must not reach apps.
    func handle(_ event: CGEvent, buttonAction: MouseAction?) -> Bool {
        guard let tick = Self.wheelTick(from: event) else {
            return false
        }
        let plan = planner.plan(tick, settings: settings, buttonAction: buttonAction, screenHeight: screenHeight)
        let flags = SyntheticEvents.currentFlags.subtracting(SyntheticEvents.flags(for: plan.consumedModifiers))
        output.flags = flags
        zoom.flags = flags
        switch plan.output {
        case .passThrough:
            return false
        case .swallow:
            return true
        case let .perform(action):
            ActionPerformer.perform(action)
            return true
        case let .scroll(dx, dy, feel):
            scroll(dx: dx, dy: dy, feel: feel, now: tick.time)
            return true
        case let .zoom(amount, feel):
            zoomBy(amount, feel: feel, now: tick.time)
            return true
        }
    }

    /// Stops all motion, for example when the tap is removed.
    func cancel() {
        animator.stop()
        zoomAnimator.stop()
        momentum.stop()
        output.forcesPhases = false
        output.end()
        zoom.end()
        clock.stop()
    }

    // MARK: - Input

    /// Nil for events that are not a plain mouse wheel notch.
    private static func wheelTick(from event: CGEvent) -> WheelTick? {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let hasPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        let subtype = event.getIntegerValueField(.mouseEventSubtype)
        let isTablet = subtype == Int64(CGEventMouseSubtype.tabletPoint.rawValue)
            || subtype == Int64(CGEventMouseSubtype.tabletProximity.rawValue)
        guard !isContinuous, !hasPhase, !isTablet else {
            return nil
        }
        let vertical = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let horizontal = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let horizontalWheel = vertical == 0
        let lines = horizontalWheel ? horizontal : vertical
        guard lines != 0 else {
            return nil
        }
        let points = event.getIntegerValueField(
            horizontalWheel ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventPointDeltaAxis1
        )
        return WheelTick(
            direction: lines > 0 ? 1 : -1,
            horizontalWheel: horizontalWheel,
            systemPixels: Double(abs(points)),
            time: CACurrentMediaTime(),
            held: SyntheticEvents.modifiers(in: event.flags)
        )
    }

    // MARK: - Drag scrolling

    /// Starts a two-finger scroll driven by mouse movement instead of the wheel.
    func beginDragScroll() {
        animator.stop()
        momentum.stop()
        output.end()
        output.flags = SyntheticEvents.currentFlags
        // Always with phases, so apps rubber-band and navigate like on a trackpad.
        output.forcesPhases = true
    }

    func dragScroll(dx: Double, dy: Double) {
        output.scroll(dx: dx, dy: dy, phase: .gesture)
    }

    func endDragScroll(velocity: Double, horizontal: Bool, now: Double) {
        momentum.start(velocity: velocity, curve: DragScroll.momentum, now: now)
        if momentum.isRunning {
            momentumHorizontally = horizontal
            clock.start()
        } else {
            output.end()
            output.forcesPhases = false
        }
    }

    // MARK: - Motion

    private func scroll(dx: Double, dy: Double, feel: ScrollFeel?, now: Double) {
        let horizontal = dx != 0
        if momentum.isRunning {
            momentum.stop()
            output.forcesPhases = false
        }
        guard let feel else {
            animator.stop()
            output.scroll(dx: dx, dy: dy, phase: .gesture)
            output.end()
            return
        }
        if animator.isRunning, horizontal != animatingHorizontally {
            animator.stop()
            output.end()
        }
        animatingHorizontally = horizontal
        animator.add(distance: horizontal ? dx : dy, feel: feel, now: now)
        clock.start()
    }

    private func zoomBy(_ amount: Double, feel: ScrollFeel?, now: Double) {
        guard let feel else {
            zoom.change(amount)
            zoom.end()
            return
        }
        zoomAnimator.add(distance: amount * Self.zoomScale, feel: feel, now: now)
        clock.start()
    }

    private func frame(now: Double) {
        if let frame = animator.frame(now: now) {
            if animatingHorizontally {
                output.scroll(dx: frame.delta, dy: 0, phase: frame.phase)
            } else {
                output.scroll(dx: 0, dy: frame.delta, phase: frame.phase)
            }
            if frame.finished {
                output.end()
            }
        }
        if let frame = zoomAnimator.frame(now: now) {
            zoom.change(frame.delta / Self.zoomScale)
            if frame.finished {
                zoom.end()
            }
        }
        if let frame = momentum.frame(now: now) {
            if momentumHorizontally {
                output.scroll(dx: frame.delta, dy: 0, phase: .momentum)
            } else {
                output.scroll(dx: 0, dy: frame.delta, phase: .momentum)
            }
            if frame.finished {
                output.end()
                output.forcesPhases = false
            }
        }
        if !animator.isRunning, !zoomAnimator.isRunning, !momentum.isRunning {
            clock.stop()
        }
    }
}

/// Posts scroll deltas as events. With trackpad simulation the events carry the
/// phases of a two-finger scroll: began, changed, ended, then momentum.
final class ScrollOutput {
    private enum State {
        case idle
        case gesture
        case momentum
    }

    var simulatesTrackpad = true
    /// Posts with phases even when trackpad simulation is off (for drag scrolling).
    var forcesPhases = false
    var flags: CGEventFlags = []

    private var state = State.idle
    private var x = SubpixelAccumulator()
    private var y = SubpixelAccumulator()

    func scroll(dx: Double, dy: Double, phase: ScrollAnimator.Phase) {
        let ix = x.take(dx)
        let iy = y.take(dy)
        let moved = ix != 0 || iy != 0
        guard simulatesTrackpad || forcesPhases else {
            if moved {
                GestureEvents.postScroll(dx: ix, dy: iy, phase: .none, momentum: .none, flags: flags)
            }
            return
        }
        switch (state, phase) {
        case (.idle, .gesture), (.momentum, .gesture):
            if state == .momentum {
                GestureEvents.postScroll(dx: 0, dy: 0, phase: .none, momentum: .end, flags: flags)
            }
            GestureEvents.postScroll(dx: ix, dy: iy, phase: .began, momentum: .none, flags: flags)
            state = .gesture
        case (.gesture, .gesture):
            if moved {
                GestureEvents.postScroll(dx: ix, dy: iy, phase: .changed, momentum: .none, flags: flags)
            }
        case (.gesture, .momentum), (.idle, .momentum):
            if state == .gesture {
                GestureEvents.postScroll(dx: 0, dy: 0, phase: .ended, momentum: .none, flags: flags)
            }
            GestureEvents.postScroll(dx: ix, dy: iy, phase: .none, momentum: .begin, flags: flags)
            state = .momentum
        case (.momentum, .momentum):
            if moved {
                GestureEvents.postScroll(dx: ix, dy: iy, phase: .none, momentum: .continue, flags: flags)
            }
        }
    }

    func end() {
        switch state {
        case .idle:
            break
        case .gesture:
            GestureEvents.postScroll(dx: 0, dy: 0, phase: .ended, momentum: .none, flags: flags)
        case .momentum:
            GestureEvents.postScroll(dx: 0, dy: 0, phase: .none, momentum: .end, flags: flags)
        }
        state = .idle
        x.reset()
        y.reset()
    }
}

/// Posts a pinch-to-zoom gesture, begun on the first change and ended by `end`.
final class ZoomOutput {
    var flags: CGEventFlags = []
    private var active = false

    func change(_ magnification: Double) {
        if !active {
            active = true
            GestureEvents.postZoom(phase: .began, magnification: 0, flags: flags)
            // Chromium ignores a pinch until it has seen a few small steps.
            for _ in 0..<3 {
                GestureEvents.postZoom(phase: .changed, magnification: magnification > 0 ? 0.001 : -0.001, flags: flags)
            }
        }
        GestureEvents.postZoom(phase: .changed, magnification: magnification, flags: flags)
    }

    func end() {
        guard active else { return }
        active = false
        GestureEvents.postZoom(phase: .ended, magnification: 0, flags: flags)
    }
}
