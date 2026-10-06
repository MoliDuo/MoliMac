import XCTest
@testable import MoliMacCore

final class RemapTableTests: XCTestCase {
    func testLeftAndRightButtonsAreNeverRemapped() {
        let table = RemapTable([
            ButtonMapping(Trigger(button: 1, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 2, kind: .click), .lookUp),
        ])
        XCTAssertTrue(table.isEmpty)
        XCTAssertFalse(table.isRemapped(button: 1))
    }

    func testMismatchedNoneAndUnknownActionsAreSkipped() {
        let table = RemapTable([
            ButtonMapping(Trigger(button: 4, kind: .click), .scrollZoom),
            ButtonMapping(Trigger(button: 4, kind: .drag), .lookUp),
            ButtonMapping(Trigger(button: 4, kind: .hold), .none),
            ButtonMapping(Trigger(button: 4, kind: .scroll), .unknown("future")),
            ButtonMapping(Trigger(button: 4, clicks: 4, kind: .click), .lookUp),
        ])
        XCTAssertTrue(table.isEmpty)
    }

    func testFirstMappingForTriggerWins() {
        let table = RemapTable([
            ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
            ButtonMapping(Trigger(button: 4, kind: .click), .spotlight),
        ])
        XCTAssertEqual(table.action(button: 4, clicks: 1, kind: .click), .lookUp)
    }

    func testDefaultMappings() {
        let table = RemapTable(MouseSettings.defaultButtons)
        XCTAssertEqual(table.action(button: 4, clicks: 1, kind: .click), .lookUp)
        XCTAssertEqual(table.action(button: 5, clicks: 1, kind: .scroll), .scrollZoom)
        XCTAssertEqual(table.action(button: 5, clicks: 1, kind: .drag), .dragScrollAndNavigate)
        XCTAssertFalse(table.isRemapped(button: 3))
        XCTAssertFalse(table.hasMappings(button: 4, beyond: 1))
        XCTAssertTrue(table.usesPress(button: 4, clicks: 1))
        XCTAssertFalse(table.usesPress(button: 4, clicks: 2))
    }
}

final class MouseActionCodingTests: XCTestCase {
    func testRoundTrip() throws {
        let actions: [MouseAction] = [
            .lookUp,
            .scrollZoom,
            .keyboardShortcut(KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift])),
        ]
        let data = try JSONEncoder().encode(actions)
        XCTAssertEqual(try JSONDecoder().decode([MouseAction].self, from: data), actions)
    }

    func testUnknownTypeIsKept() throws {
        let data = Data(#"{"type":"teleport"}"#.utf8)
        let action = try JSONDecoder().decode(MouseAction.self, from: data)
        XCTAssertEqual(action, .unknown("teleport"))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(action)) as? [String: String]
        XCTAssertEqual(encoded, ["type": "teleport"])
    }

    func testChoicesMatchTriggerKind() {
        for kind in TriggerKind.allCases {
            for action in MouseAction.choices(for: kind) {
                XCTAssertEqual(action.kind, kind.actionKind, "\(action) offered for \(kind)")
            }
        }
    }
}

final class NavigationTests: XCTestCase {
    func testAppleAppsSwipe() {
        XCTAssertEqual(NavigationMethod.forApp(bundleIdentifier: "com.apple.Safari"), .swipe)
        XCTAssertEqual(NavigationMethod.forApp(bundleIdentifier: "com.apple.finder"), .swipe)
    }

    func testOtherAppsUseMouseButtons() {
        XCTAssertEqual(NavigationMethod.forApp(bundleIdentifier: "com.google.Chrome"), .mouseButtons)
        XCTAssertEqual(NavigationMethod.forApp(bundleIdentifier: nil), .mouseButtons)
    }

    func testOverrides() {
        guard case let .keys(back, forward) = NavigationMethod.forApp(bundleIdentifier: "com.apple.Notes") else {
            return XCTFail("Notes should use keys")
        }
        XCTAssertEqual(back.modifiers, [.option, .command])
        XCTAssertEqual(forward.keyCode, 30)
        XCTAssertEqual(NavigationMethod.forApp(bundleIdentifier: "com.operasoftware.Opera"), .swipe)
    }

    func testSymbolicHotKeys() {
        XCTAssertEqual(SymbolicHotKey(action: .missionControl)?.rawValue, 32)
        XCTAssertEqual(SymbolicHotKey(action: .launchpad)?.unreachableKeyCode, 560)
        XCTAssertNil(SymbolicHotKey(action: .back))
    }
}
