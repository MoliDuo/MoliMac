import XCTest
@testable import MoliMacCore

final class SpacesDragTests: XCTestCase {
    func testSmallMovementDoesNothing() {
        var drag = SpacesDrag()
        XCTAssertEqual(drag.move(dx: 30, dy: 20), [])
    }

    func testSidewaysSwitchesDesktopsAndKeepsGoing() {
        var drag = SpacesDrag()
        XCTAssertEqual(drag.move(dx: 70, dy: 10), [.spaceLeft])
        XCTAssertEqual(drag.move(dx: 100, dy: -50), [])
        XCTAssertEqual(drag.move(dx: 100, dy: 0), [.spaceLeft])
        // Back the other way: a full step past the last switch.
        XCTAssertEqual(drag.move(dx: -200, dy: 0), [.spaceRight])
        XCTAssertEqual(drag.move(dx: -400, dy: 0), [.spaceRight, .spaceRight])
    }

    func testUpOpensMissionControlOnce() {
        var drag = SpacesDrag()
        XCTAssertEqual(drag.move(dx: 5, dy: -70), [.missionControl])
        XCTAssertEqual(drag.move(dx: 300, dy: -300), [])
    }

    func testDownShowsAppWindows() {
        var drag = SpacesDrag()
        XCTAssertEqual(drag.move(dx: 0, dy: 80), [.appExpose])
    }
}

final class DragScrollTests: XCTestCase {
    func testAxisLocksAndContentFollowsThePointer() {
        var drag = DragScroll()
        XCTAssertTrue(drag.move(dx: 1, dy: 2, time: 0) == (0, 0))
        let locked = drag.move(dx: 0, dy: 3, time: 0.01)
        XCTAssertEqual(drag.axis, .vertical)
        XCTAssertEqual(locked.dx, 0)
        XCTAssertEqual(locked.dy, 5 * DragScroll.gain, accuracy: 1e-9)
        // Sideways movement is ignored once the axis is vertical.
        let next = drag.move(dx: 10, dy: -2, time: 0.02)
        XCTAssertEqual(next.dx, 0)
        XCTAssertEqual(next.dy, -2 * DragScroll.gain, accuracy: 1e-9)
    }

    func testReleaseVelocity() {
        var drag = DragScroll()
        for step in 0..<10 {
            _ = drag.move(dx: 10, dy: 0, time: Double(step) * 0.01)
        }
        XCTAssertEqual(drag.releaseVelocity(at: 0.1), 10 * DragScroll.gain / 0.01, accuracy: 1)
        XCTAssertEqual(drag.releaseVelocity(at: 0.5), 0, "a mouse that stopped before release does not glide")
    }
}

final class MomentumAnimatorTests: XCTestCase {
    func testGlideCoversTheCurveDistance() {
        var animator = MomentumAnimator()
        let curve = DragScroll.momentum
        animator.start(velocity: -2000, curve: curve, now: 1)
        var total = 0.0
        var time = 1.0
        while let frame = animator.frame(now: time) {
            total += frame.delta
            XCTAssertLessThanOrEqual(frame.delta, 0)
            time += 1.0 / 120
            if frame.finished {
                break
            }
        }
        XCTAssertFalse(animator.isRunning)
        XCTAssertEqual(total, -curve.distance(from: 2000), accuracy: 0.5)
    }

    func testSlowReleaseDoesNotGlide() {
        var animator = MomentumAnimator()
        animator.start(velocity: 0.5, curve: DragScroll.momentum, now: 0)
        XCTAssertFalse(animator.isRunning)
    }
}
