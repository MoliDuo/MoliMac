import XCTest
@testable import MoliMacCore

final class AppProfileTests: XCTestCase {
    func testUnknownAppsUseTheGlobalSettings() {
        let settings = MouseSettings()
        XCTAssertEqual(settings.profile(for: "com.example.editor"), settings.globalProfile)
        XCTAssertEqual(settings.profile(for: nil), settings.globalProfile)
        XCTAssertFalse(settings.hasAppSettings)
    }

    func testExcludedAppIsDisabled() {
        var settings = MouseSettings()
        settings.excludedApps = ["com.example.game"]
        XCTAssertFalse(settings.profile(for: "com.example.game").enabled)
        XCTAssertTrue(settings.profile(for: "com.example.editor").enabled)
    }

    func testOverridesReplaceOnlyWhatTheySet() {
        var settings = MouseSettings()
        var override = AppOverride(bundleIdentifier: "com.example.editor")
        override.scroll.reverse = true
        override.scroll.smoothness = .off
        settings.apps = [override]

        let profile = settings.profile(for: "com.example.editor")
        XCTAssertEqual(profile.buttons, settings.buttons)
        XCTAssertTrue(profile.scroll.reverse)
        XCTAssertEqual(profile.scroll.smoothness, .off)
        XCTAssertEqual(profile.scroll.speed, settings.scroll.speed)
        XCTAssertEqual(profile.scroll.modifiers, settings.scroll.modifiers)

        settings.apps[0].buttons = []
        XCTAssertEqual(settings.profile(for: "com.example.editor").buttons, [])
    }
}

final class AppSettingsCodingTests: XCTestCase {
    func testNewFieldsRoundTrip() throws {
        var settings = AppSettings()
        settings.mouse.pointer.acceleration = false
        settings.mouse.pointer.speed = 1.5
        var override = AppOverride(bundleIdentifier: "com.example.editor")
        override.buttons = [ButtonMapping(Trigger(button: 4, kind: .click), .autoscroll)]
        override.scroll.speed = .high
        settings.mouse.apps = [override]

        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testClearedOptionalsAreWrittenAsNull() throws {
        let data = try JSONEncoder().encode(PointerSettings())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object["acceleration"] is NSNull, "a left-out key would keep its old value in the merged file")
        XCTAssertTrue(object["speed"] is NSNull)
    }

    func testOldFilesWithoutTheNewFieldsLoad() throws {
        let json = Data(#"{"schemaVersion":1,"mouse":{"enabled":false}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(settings.mouse.enabled)
        XCTAssertEqual(settings.mouse.pointer, PointerSettings())
        XCTAssertEqual(settings.mouse.apps, [])
    }

    func testPointerSpeedIsClamped() throws {
        let json = Data(#"{"acceleration":true,"speed":40}"#.utf8)
        let pointer = try JSONDecoder().decode(PointerSettings.self, from: json)
        XCTAssertEqual(pointer.speed, PointerSettings.speedRange.upperBound)
        XCTAssertEqual(pointer.acceleration, true)
    }
}

final class AutoscrollTests: XCTestCase {
    func testDeadZoneAndDirection() {
        XCTAssertEqual(Autoscroll.velocity(offset: 0), 0)
        XCTAssertEqual(Autoscroll.velocity(offset: -Autoscroll.deadZone), 0)
        XCTAssertLessThan(Autoscroll.velocity(offset: 40), 0, "pointer below the start scrolls down")
        XCTAssertGreaterThan(Autoscroll.velocity(offset: -40), 0)
        XCTAssertGreaterThan(abs(Autoscroll.velocity(offset: 200)), abs(Autoscroll.velocity(offset: 40)))
        XCTAssertEqual(Autoscroll.velocity(offset: 100_000), -Autoscroll.maxSpeed)
    }
}
