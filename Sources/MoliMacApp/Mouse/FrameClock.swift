import AppKit
import QuartzCore

/// Calls `onFrame` on the event tap thread once per display refresh while running,
/// with the time the frame will appear (`CACurrentMediaTime` clock).
///
/// Uses `CADisplayLink`: Mac Mouse Fix ran into deadlocks with CVDisplayLink. Without
/// a screen it falls back to a 120 Hz timer.
final class FrameClock: NSObject, @unchecked Sendable {
    private let thread: EventTapThread
    private var link: CADisplayLink?
    private var timer: CFRunLoopTimer?
    private var running = false

    /// Set before `start` and only touched on the tap thread.
    var onFrame: ((Double) -> Void)?

    @MainActor
    init(thread: EventTapThread) {
        self.thread = thread
        super.init()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        link.isPaused = true
        let box = UncheckedBox(link)
        thread.perform { [self] in
            guard let runLoop = thread.foundationRunLoop else { return }
            box.value.add(to: runLoop, forMode: .common)
            self.link = box.value
        }
    }

    /// On the tap thread.
    func start() {
        guard !running else { return }
        running = true
        if let link {
            link.isPaused = false
        } else if let runLoop = thread.runLoop {
            let interval = 1.0 / 120
            let timer = CFRunLoopTimerCreateWithHandler(
                kCFAllocatorDefault,
                CFAbsoluteTimeGetCurrent() + interval,
                interval, 0, 0
            ) { [weak self] _ in
                self?.onFrame?(CACurrentMediaTime())
            }
            CFRunLoopAddTimer(runLoop, timer, .commonModes)
            self.timer = timer
        }
    }

    /// On the tap thread.
    func stop() {
        guard running else { return }
        running = false
        link?.isPaused = true
        if let timer {
            CFRunLoopTimerInvalidate(timer)
        }
        timer = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        onFrame?(link.targetTimestamp)
    }
}

/// Hands a non-Sendable object to another thread that alone uses it from then on.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
