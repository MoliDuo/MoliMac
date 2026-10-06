import Foundation

/// A thread with its own run loop for event taps, timers and the scroll display link.
///
/// Event taps are disabled by the system when their callback is slow, so they get a
/// thread that never waits on the main thread. Everything the mouse engine owns is
/// touched only on this thread; other threads hand work over with `perform`.
final class EventTapThread: Thread, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private(set) var runLoop: CFRunLoop?
    private(set) var foundationRunLoop: RunLoop?

    override init() {
        super.init()
        name = "com.moliduo.mac.event-tap"
        qualityOfService = .userInteractive
    }

    func startAndWait() {
        start()
        ready.wait()
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        foundationRunLoop = RunLoop.current
        // A run loop with no sources returns at once; the port keeps this one alive.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            _ = autoreleasepool {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }
    }

    func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs `block` on this thread after `delay` seconds.
    func perform(after delay: Double, _ block: @escaping @Sendable () -> Void) {
        guard let runLoop else { return }
        let timer = CFRunLoopTimerCreateWithHandler(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + delay,
            0, 0, 0
        ) { _ in block() }
        CFRunLoopAddTimer(runLoop, timer, .commonModes)
    }

    func stop() {
        cancel()
        perform {}
    }
}
