import XCTest
@testable import MoliMacCore

final class ButtonListTests: XCTestCase {
    func testAddButtonAddsAnEmptyClickRowOnce() {
        var mappings: [ButtonMapping] = []
        XCTAssertTrue(ButtonList.addButton(6, to: &mappings))
        XCTAssertFalse(ButtonList.addButton(6, to: &mappings))
        XCTAssertEqual(mappings, [ButtonMapping(Trigger(button: 6, kind: .click), .none)])
        XCTAssertTrue(RemapTable(mappings).isEmpty, "an empty row must not change what the mouse does")
    }

    func testLeftAndRightButtonsCannotBeAdded() {
        var mappings: [ButtonMapping] = []
        XCTAssertFalse(ButtonList.addButton(1, to: &mappings))
        XCTAssertFalse(ButtonList.addButton(2, to: &mappings))
        XCTAssertTrue(mappings.isEmpty)
    }

    func testRowsAreGroupedAndSorted() {
        let mappings = [
            ButtonMapping(Trigger(button: 5, kind: .scroll), .scrollZoom),
            ButtonMapping(Trigger(button: 4, clicks: 2, kind: .click), .spotlight),
            ButtonMapping(Trigger(button: 4, kind: .drag), .dragSpacesAndMissionControl),
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
        ]
        XCTAssertEqual(ButtonList.buttons(in: mappings), [4, 5])
        XCTAssertEqual(
            ButtonList.mappings(for: 4, in: mappings).map(\.trigger),
            [
                Trigger(button: 4, kind: .click),
                Trigger(button: 4, kind: .drag),
                Trigger(button: 4, clicks: 2, kind: .click),
            ]
        )
    }

    func testUnusedTriggersSkipThoseWithRows() {
        let mappings = MouseSettings.defaultButtons
        let unused = ButtonList.unusedTriggers(for: 4, in: mappings)
        XCTAssertEqual(unused.first, Trigger(button: 4, kind: .hold))
        XCTAssertEqual(unused.count, Trigger.maxClicks * TriggerKind.allCases.count - 3)
        XCTAssertFalse(unused.contains(Trigger(button: 4, kind: .click)))
    }

    func testSetActionAndRemove() {
        var mappings: [ButtonMapping] = []
        let trigger = Trigger(button: 3, kind: .hold)
        ButtonList.add(trigger, to: &mappings)
        ButtonList.add(trigger, to: &mappings)
        XCTAssertEqual(mappings.count, 1)

        ButtonList.setAction(.missionControl, for: trigger, in: &mappings)
        XCTAssertEqual(RemapTable(mappings).action(button: 3, clicks: 1, kind: .hold), .missionControl)

        ButtonList.remove(trigger, from: &mappings)
        XCTAssertTrue(mappings.isEmpty)
    }
}
