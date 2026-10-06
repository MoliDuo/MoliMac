import XCTest
@testable import MoliMacCore

final class SettingsStoreTests: XCTestCase {
    private var directory: URL!
    private var url: URL {
        directory.appendingPathComponent("settings.json")
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoliMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func readJSON() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }

    func testMissingFileMeansDefaults() throws {
        let store = SettingsStore(url: url)
        guard case .missing = store.load() else {
            return XCTFail("expected missing")
        }
        try store.save(AppSettings())
        guard case let .loaded(settings) = store.load() else {
            return XCTFail("expected loaded")
        }
        XCTAssertEqual(settings, AppSettings())
    }

    func testRoundTripKeepsChanges() throws {
        let store = SettingsStore(url: url)
        var settings = AppSettings()
        settings.mouse.scroll.smoothness = .low
        settings.mouse.scroll.modifiers.zoom = nil
        settings.mouse.excludedApps = ["com.example.game"]
        try store.save(settings)
        guard case let .loaded(loaded) = SettingsStore(url: url).load() else {
            return XCTFail("expected loaded")
        }
        XCTAssertEqual(loaded, settings)
    }

    func testMissingFieldsTakeDefaults() throws {
        try Data(#"{"schemaVersion":1,"mouse":{"scroll":{"reverse":true}}}"#.utf8).write(to: url)
        guard case let .loaded(settings) = SettingsStore(url: url).load() else {
            return XCTFail("expected loaded")
        }
        XCTAssertTrue(settings.mouse.scroll.reverse)
        XCTAssertEqual(settings.mouse.scroll.smoothness, .high)
        XCTAssertEqual(settings.mouse.scroll.modifiers.zoom, .command)
        XCTAssertEqual(settings.mouse.buttons, MouseSettings.defaultButtons)
    }

    func testUnknownFieldsSurviveSave() throws {
        let json = #"{"schemaVersion":1,"future":{"a":1},"mouse":{"enabled":true,"newThing":"x"}}"#
        try Data(json.utf8).write(to: url)
        let store = SettingsStore(url: url)
        guard case var .loaded(settings) = store.load() else {
            return XCTFail("expected loaded")
        }
        settings.mouse.enabled = false
        try store.save(settings)

        let saved = try readJSON()
        XCTAssertEqual((saved["future"] as? [String: Int])?["a"], 1)
        let mouse = try XCTUnwrap(saved["mouse"] as? [String: Any])
        XCTAssertEqual(mouse["newThing"] as? String, "x")
        XCTAssertEqual(mouse["enabled"] as? Bool, false)
    }

    func testUnreadableFileIsNotOverwritten() throws {
        let broken = Data("{ not json".utf8)
        try broken.write(to: url)
        let store = SettingsStore(url: url)
        guard case .unreadable = store.load() else {
            return XCTFail("expected unreadable")
        }
        XCTAssertThrowsError(try store.save(AppSettings()))
        XCTAssertEqual(try Data(contentsOf: url), broken)

        let backup = try XCTUnwrap(store.resetToDefaults())
        XCTAssertEqual(try Data(contentsOf: backup), broken)
        guard case .loaded = store.load() else {
            return XCTFail("expected loaded after reset")
        }
    }

    func testExplicitNullTurnsModifierOff() throws {
        try Data(#"{"mouse":{"scroll":{"modifiers":{"swift":null}}}}"#.utf8).write(to: url)
        guard case let .loaded(settings) = SettingsStore(url: url).load() else {
            return XCTFail("expected loaded")
        }
        XCTAssertNil(settings.mouse.scroll.modifiers.swift)
        XCTAssertEqual(settings.mouse.scroll.modifiers.horizontal, .shift)
    }
}
