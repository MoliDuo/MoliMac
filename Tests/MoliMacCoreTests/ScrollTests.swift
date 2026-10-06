import XCTest
@testable import MoliMacCore

final class ScrollCurveTests: XCTestCase {
    private let drag = DragCurve(coefficient: 40, exponent: 0.7, stopSpeed: 30)

    func testDragCurveClosedFormsAgree() {
        let v0 = 1500.0
        let end = drag.duration(from: v0)
        XCTAssertGreaterThan(end, 0)
        XCTAssertEqual(drag.velocity(at: end, from: v0), 30, accuracy: 1e-6)
        XCTAssertEqual(drag.position(at: end, from: v0), drag.distance(from: v0), accuracy: 1e-6)
        XCTAssertEqual(drag.position(at: end + 1, from: v0), drag.distance(from: v0), accuracy: 1e-6)
    }

    func testDragCurveBelowStopSpeedIsStill() {
        XCTAssertEqual(drag.duration(from: 10), 0)
        XCTAssertEqual(drag.distance(from: 10), 0)
    }

    func testHybridCurveCoversDistanceAndIsMonotonic() {
        let curve = HybridCurve(distance: 120, baseDuration: 0.22, drag: drag)
        XCTAssertLessThan(curve.baseDistance, 120)
        XCTAssertGreaterThan(curve.duration, 0.22)
        XCTAssertEqual(curve.baseDistance + drag.distance(from: curve.handoverSpeed), 120, accuracy: 1e-6)

        var previous = 0.0
        var t = 0.0
        while t <= curve.duration + 0.05 {
            let p = curve.position(at: t)
            XCTAssertGreaterThanOrEqual(p, previous - 1e-9)
            previous = p
            t += 1.0 / 120
        }
        XCTAssertEqual(curve.position(at: curve.duration), 120, accuracy: 1e-9)
    }

    func testHybridCurveIsContinuousAtHandover() {
        let curve = HybridCurve(distance: 300, baseDuration: 0.22, drag: drag)
        let before = curve.position(at: 0.22 - 1e-9)
        let after = curve.position(at: 0.22 + 1e-9)
        XCTAssertEqual(before, after, accuracy: 1e-3)
    }

    func testCurveWithoutDragEndsWithBase() {
        let curve = HybridCurve(distance: 60, baseDuration: 0.09, easing: 0.8, drag: nil)
        XCTAssertEqual(curve.duration, 0.09)
        XCTAssertEqual(curve.position(at: 0.09), 60)
        XCTAssertFalse(curve.isMomentum(at: 0.05))
    }

    func testMomentumIsTheTail() {
        let curve = HybridCurve(distance: 300, baseDuration: 0.22, drag: drag)
        XCTAssertFalse(curve.isMomentum(at: 0.1))
        XCTAssertTrue(curve.isMomentum(at: 0.3))
        XCTAssertFalse(curve.isMomentum(at: curve.duration))
    }
}

final class ScrollAnimatorTests: XCTestCase {
    private let feel = ScrollFeel.smoothness(.high)!

    private func run(_ animator: inout ScrollAnimator, from start: Double, until end: Double) -> Double {
        var total = 0.0
        var t = start
        while t <= end, let frame = animator.frame(now: t) {
            total += frame.delta
            t += 1.0 / 120
        }
        return total
    }

    func testFramesAddUpToDistance() {
        var animator = ScrollAnimator()
        animator.add(distance: 120, feel: feel, now: 0)
        XCTAssertEqual(run(&animator, from: 0, until: 10), 120, accuracy: 1e-6)
        XCTAssertFalse(animator.isRunning)
    }

    func testSecondTickAddsRemainder() {
        var animator = ScrollAnimator()
        animator.add(distance: 100, feel: feel, now: 0)
        let first = run(&animator, from: 0, until: 0.05)
        animator.add(distance: 100, feel: feel, now: 0.05)
        let rest = run(&animator, from: 0.05, until: 10)
        XCTAssertEqual(first + rest, 200, accuracy: 1e-6)
    }

    func testReversingDropsRemainder() {
        var animator = ScrollAnimator()
        animator.add(distance: 100, feel: feel, now: 0)
        let first = run(&animator, from: 0, until: 0.05)
        animator.add(distance: -100, feel: feel, now: 0.05)
        let rest = run(&animator, from: 0.05, until: 10)
        XCTAssertGreaterThan(first, 0)
        XCTAssertEqual(rest, -100, accuracy: 1e-6)
    }

    func testSubpixelAccumulatorKeepsRemainder() {
        var accumulator = SubpixelAccumulator()
        var sum = 0
        for _ in 0..<10 {
            sum += accumulator.take(0.35)
        }
        XCTAssertEqual(sum, 3)
        XCTAssertEqual(accumulator.take(-0.6), 0)
    }
}

final class ScrollAccelerationTests: XCTestCase {
    func testFirstTickOfSwipeIsSlowest() {
        var acceleration = ScrollAcceleration()
        let tick = acceleration.tick(at: 0)
        XCTAssertEqual(tick.intensity, 0)
        XCTAssertEqual(tick.flings, 0)
    }

    func testFastTicksRaiseIntensity() {
        var acceleration = ScrollAcceleration()
        _ = acceleration.tick(at: 0)
        var intensity = 0.0
        var t = 0.0
        for _ in 0..<10 {
            t += 0.02
            intensity = acceleration.tick(at: t).intensity
        }
        XCTAssertGreaterThan(intensity, 0.5)
        XCTAssertLessThanOrEqual(intensity, 1)
    }

    func testRepeatedSwipesFling() {
        var acceleration = ScrollAcceleration()
        var t = 0.0
        var flings = 0
        for _ in 0..<3 {
            for _ in 0..<4 {
                flings = acceleration.tick(at: t).flings
                t += 0.03
            }
            t += 0.3
        }
        flings = acceleration.tick(at: t).flings
        XCTAssertGreaterThanOrEqual(flings, 2)
    }

    func testPixels() throws {
        let range = try XCTUnwrap(ScrollAcceleration.range(for: .medium))
        XCTAssertEqual(ScrollAcceleration.pixels(range: range, intensity: 0, flings: 0), 60)
        XCTAssertEqual(ScrollAcceleration.pixels(range: range, intensity: 1, flings: 0), 120)
        XCTAssertEqual(ScrollAcceleration.pixels(range: range, intensity: 1, flings: 100), 480)
        XCTAssertNil(ScrollAcceleration.range(for: .system))
        XCTAssertEqual(ScrollAcceleration.precisePixels(intensity: 0), 3)
    }
}
