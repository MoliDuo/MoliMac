import XCTest
@testable import MoliMacCore

final class ClickCycleTests: XCTestCase {
    private func cycle(_ mappings: [ButtonMapping]) -> ClickCycle {
        ClickCycle(table: RemapTable(mappings))
    }

    /// Presses and returns the timer token the cycle asked for.
    private func press(_ cycle: inout ClickCycle, _ button: Int) -> Int {
        let effects = cycle.press(button: button)
        for case let .scheduleTimers(token) in effects {
            return token
        }
        XCTFail("press did not schedule timers")
        return -1
    }

    func testClickPerformsOnReleaseWhenNothingElseIsMapped() {
        var c = cycle([ButtonMapping(Trigger(button: 4, kind: .click), .lookUp)])
        _ = press(&c, 4)
        let (effects, passThrough) = c.release(button: 4)
        XCTAssertEqual(effects, [.perform(.lookUp)])
        XCTAssertFalse(passThrough)
        XCTAssertTrue(c.isIdle)
    }

    func testClickWaitsForLevelTimerWhenDoubleClickIsMapped() {
        var c = cycle([
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 4, clicks: 2, kind: .click), .missionControl),
        ])
        let token = press(&c, 4)
        XCTAssertEqual(c.release(button: 4).effects, [])
        XCTAssertEqual(c.levelTimerFired(token: token), [.perform(.lookUp)])
        XCTAssertTrue(c.isIdle)
    }

    func testDoubleClick() {
        var c = cycle([
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 4, clicks: 2, kind: .click), .missionControl),
        ])
        let first = press(&c, 4)
        _ = c.release(button: 4)
        let second = press(&c, 4)
        // The first press's timer is stale now.
        XCTAssertEqual(c.levelTimerFired(token: first), [])
        XCTAssertEqual(c.release(button: 4).effects, [.perform(.missionControl)])
        XCTAssertEqual(c.levelTimerFired(token: second), [])
        XCTAssertTrue(c.isIdle)
    }

    func testSecondClickAfterLevelClosedStartsNewCycle() {
        var c = cycle([
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 4, kind: .hold), .missionControl),
        ])
        let token = press(&c, 4)
        // Held past the click level without the hold firing first is impossible in
        // practice, but the level closing must stop the next press from counting.
        _ = c.levelTimerFired(token: token)
        XCTAssertEqual(c.release(button: 4).effects, [.perform(.lookUp)])
        _ = press(&c, 4)
        XCTAssertEqual(c.release(button: 4).effects, [.perform(.lookUp)])
    }

    func testHold() {
        var c = cycle([
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 4, kind: .hold), .missionControl),
        ])
        let token = press(&c, 4)
        XCTAssertEqual(c.holdTimerFired(token: token), [.perform(.missionControl)])
        let (effects, passThrough) = c.release(button: 4)
        XCTAssertEqual(effects, [])
        XCTAssertFalse(passThrough)
        XCTAssertTrue(c.isIdle)
    }

    func testHoldTimerWithoutHoldMappingDoesNothing() {
        var c = cycle([ButtonMapping(Trigger(button: 4, kind: .click), .lookUp)])
        let token = press(&c, 4)
        XCTAssertEqual(c.holdTimerFired(token: token), [])
        XCTAssertEqual(c.release(button: 4).effects, [.perform(.lookUp)])
    }

    func testDragStartsPastThreshold() {
        var c = cycle([ButtonMapping(Trigger(button: 4, kind: .drag), .dragSpacesAndMissionControl)])
        _ = press(&c, 4)
        XCTAssertFalse(c.move(dx: 3, dy: 0).consumed)
        let (effects, consumed) = c.move(dx: 4, dy: 0)
        XCTAssertEqual(effects, [.beginDrag(.dragSpacesAndMissionControl)])
        XCTAssertTrue(consumed)
        XCTAssertTrue(c.isDragging)
        XCTAssertTrue(c.move(dx: 50, dy: 0).consumed)
        XCTAssertEqual(c.release(button: 4).effects, [.endDrag])
        XCTAssertTrue(c.isIdle)
    }

    func testUnmappedDragReplaysPressAndPassesRelease() {
        var c = cycle([ButtonMapping(Trigger(button: 3, kind: .click), .missionControl)])
        _ = press(&c, 3)
        let (effects, consumed) = c.move(dx: 0, dy: -10)
        XCTAssertEqual(effects, [.replayPress(button: 3)])
        XCTAssertFalse(consumed)
        XCTAssertEqual(c.move(dx: 0, dy: -10).effects, [])
        let release = c.release(button: 3)
        XCTAssertEqual(release.effects, [])
        XCTAssertTrue(release.passThrough)
    }

    func testUnmappedClickIsReplayed() {
        var c = cycle([ButtonMapping(Trigger(button: 4, kind: .scroll), .scrollZoom)])
        _ = press(&c, 4)
        XCTAssertEqual(c.release(button: 4).effects, [.replayClick(button: 4, count: 1)])
    }

    func testScrollWhileHeld() {
        var c = cycle([ButtonMapping(Trigger(button: 5, kind: .scroll), .scrollZoom)])
        _ = press(&c, 5)
        let first = c.scroll()
        XCTAssertEqual(first.effects, [.beginScroll(.scrollZoom)])
        XCTAssertEqual(first.action, .scrollZoom)
        let second = c.scroll()
        XCTAssertEqual(second.effects, [])
        XCTAssertEqual(second.action, .scrollZoom)
        // Movement during a scroll gesture is ordinary pointer movement.
        XCTAssertFalse(c.move(dx: 20, dy: 0).consumed)
        XCTAssertEqual(c.release(button: 5).effects, [.endScroll])
    }

    func testScrollWithoutMappingIsOrdinary() {
        var c = cycle([ButtonMapping(Trigger(button: 4, kind: .click), .lookUp)])
        XCTAssertNil(c.scroll().action)
        _ = press(&c, 4)
        XCTAssertNil(c.scroll().action)
    }

    func testDoubleClickAndDrag() {
        var c = cycle([
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 4, clicks: 2, kind: .drag), .dragScrollAndNavigate),
        ])
        _ = press(&c, 4)
        _ = c.release(button: 4)
        _ = press(&c, 4)
        XCTAssertEqual(c.move(dx: 10, dy: 0).effects, [.beginDrag(.dragScrollAndNavigate)])
        XCTAssertEqual(c.release(button: 4).effects, [.endDrag])
    }

    func testPressingAnotherButtonFlushesWaitingClick() {
        var c = cycle([
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 4, clicks: 2, kind: .click), .missionControl),
            ButtonMapping(Trigger(button: 5, kind: .click), .smartZoom),
        ])
        _ = press(&c, 4)
        _ = c.release(button: 4)
        let effects = c.press(button: 5)
        XCTAssertEqual(effects.first, .perform(.lookUp))
        XCTAssertEqual(c.release(button: 5).effects, [.perform(.smartZoom)])
    }

    func testTripleClickPerformsAtOnceAndFourthPressStartsOver() {
        var c = cycle([
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 4, clicks: 3, kind: .click), .missionControl),
        ])
        _ = press(&c, 4)
        XCTAssertEqual(c.release(button: 4).effects, [])
        _ = press(&c, 4)
        XCTAssertEqual(c.release(button: 4).effects, [])
        _ = press(&c, 4)
        XCTAssertEqual(c.release(button: 4).effects, [.perform(.missionControl)])
        let token = press(&c, 4)
        _ = c.release(button: 4)
        XCTAssertEqual(c.levelTimerFired(token: token), [.perform(.lookUp)])
    }

    func testReleaseOfUnknownPressPassesThrough() {
        var c = cycle([ButtonMapping(Trigger(button: 4, kind: .click), .lookUp)])
        let (effects, passThrough) = c.release(button: 4)
        XCTAssertEqual(effects, [])
        XCTAssertTrue(passThrough)
    }

    func testCancelEndsDrag() {
        var c = cycle([ButtonMapping(Trigger(button: 4, kind: .drag), .dragMiddleButton)])
        _ = press(&c, 4)
        _ = c.move(dx: 10, dy: 10)
        XCTAssertEqual(c.cancel(), [.endDrag])
        XCTAssertTrue(c.isIdle)
    }
}
