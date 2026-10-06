import XCTest
@testable import MoliMacCore

final class ScrollPlannerTests: XCTestCase {
    private func tick(
        _ direction: Int = 1,
        at time: Double = 10,
        held: Set<ModifierKey> = [],
        horizontalWheel: Bool = false
    ) -> WheelTick {
        WheelTick(direction: direction, horizontalWheel: horizontalWheel, systemPixels: 10, time: time, held: held)
    }

    private func plan(
        _ tick: WheelTick,
        settings: ScrollSettings = ScrollSettings(),
        button: MouseAction? = nil
    ) -> ScrollPlan {
        var planner = ScrollPlanner()
        return planner.plan(tick, settings: settings, buttonAction: button, screenHeight: 1000)
    }

    func testDefaultTickScrollsUpSmoothly() {
        let result = plan(tick(1))
        XCTAssertEqual(result.output, .scroll(dx: 0, dy: 60, feel: .smoothness(.high)))
        XCTAssertTrue(result.consumedModifiers.isEmpty)
    }

    func testReverseFlipsDirection() {
        var settings = ScrollSettings()
        settings.reverse = true
        XCTAssertEqual(plan(tick(1), settings: settings).output, .scroll(dx: 0, dy: -60, feel: .smoothness(.high)))
    }

    func testUntouchedSettingsPassTheEventThrough() {
        var settings = ScrollSettings()
        settings.smoothness = .off
        settings.speed = .system
        settings.trackpadSimulation = false
        XCTAssertEqual(plan(tick(-1), settings: settings).output, .passThrough)
    }

    func testModifiersPickTheModeAndAreConsumed() {
        let shift = plan(tick(-1, held: [.shift]))
        XCTAssertEqual(shift.output, .scroll(dx: -60, dy: 0, feel: .smoothness(.high)))
        XCTAssertEqual(shift.consumedModifiers, [.shift])

        let zoom = plan(tick(1, held: [.command]))
        XCTAssertEqual(zoom.output, .zoom(ScrollPlanner.zoomRange.lowerBound, feel: .smoothness(.high)))
        XCTAssertEqual(zoom.consumedModifiers, [.command])

        let swift = plan(tick(1, held: [.control]))
        XCTAssertEqual(swift.output, .scroll(dx: 0, dy: 500, feel: .swift))

        let precise = plan(tick(1, held: [.option]))
        XCTAssertEqual(precise.output, .scroll(dx: 0, dy: ScrollAcceleration.preciseRange.lowerBound, feel: .precise))
    }

    func testTurnedOffModifierIsIgnored() {
        var settings = ScrollSettings()
        settings.modifiers.horizontal = nil
        let result = plan(tick(1, held: [.shift]), settings: settings)
        XCTAssertEqual(result.output, .scroll(dx: 0, dy: 60, feel: .smoothness(.high)))
        XCTAssertTrue(result.consumedModifiers.isEmpty)
    }

    func testHorizontalWheelScrollsSideways() {
        XCTAssertEqual(
            plan(tick(1, horizontalWheel: true)).output,
            .scroll(dx: 60, dy: 0, feel: .smoothness(.high))
        )
    }

    func testPrecisionWhenTurningSlowly() {
        var settings = ScrollSettings()
        settings.precision = true
        var planner = ScrollPlanner()
        let first = planner.plan(tick(1, at: 1), settings: settings, buttonAction: nil, screenHeight: 1000)
        XCTAssertEqual(first.output, .scroll(dx: 0, dy: ScrollAcceleration.precisionTick, feel: .precise))
        let fast = planner.plan(tick(1, at: 1.02), settings: settings, buttonAction: nil, screenHeight: 1000)
        guard case let .scroll(_, dy, feel) = fast.output else {
            return XCTFail("expected a scroll")
        }
        XCTAssertGreaterThan(dy, ScrollAcceleration.precisionTick)
        XCTAssertEqual(feel, .smoothness(.high))
    }

    func testDesktopAndLaunchpadActsOncePerSwipe() {
        var planner = ScrollPlanner()
        func run(_ direction: Int, _ time: Double) -> ScrollPlan.Output {
            planner.plan(
                tick(direction, at: time),
                settings: ScrollSettings(),
                buttonAction: .scrollDesktopAndLaunchpad,
                screenHeight: 1000
            ).output
        }
        XCTAssertEqual(run(1, 1), .perform(.launchpad))
        XCTAssertEqual(run(1, 1.05), .swallow)
        XCTAssertEqual(run(-1, 2), .perform(.showDesktop))
    }

    func testButtonScrollActionsOverrideModifiers() {
        let result = plan(tick(1, held: [.shift]), button: .scrollZoom)
        XCTAssertEqual(result.output, .zoom(ScrollPlanner.zoomRange.lowerBound, feel: .smoothness(.high)))
        XCTAssertTrue(result.consumedModifiers.isEmpty)
    }
}
