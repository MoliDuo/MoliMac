import Foundation

/// Everything the user can change, saved as `settings.json` (MoliSpec 009).
///
/// Fields are only ever added. Every field decodes with a default when it is
/// missing, so a file written by an older version still loads, and the store keeps
/// fields this version does not know when it writes the file back.
public struct AppSettings: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Self.currentSchemaVersion
    public var general = GeneralSettings()
    public var mouse = MouseSettings()

    public init() {}
}

public struct GeneralSettings: Equatable, Sendable {
    public var showMenuBarIcon = true

    public init() {}
}

public struct MouseSettings: Equatable, Sendable {
    public var enabled = true
    public var buttons = Self.defaultButtons
    public var scroll = ScrollSettings()
    /// Bundle identifiers of apps where the mouse module does nothing.
    public var excludedApps: [String] = []

    public init() {}

    /// The setup the user had in Mac Mouse Fix when MoliMac replaced it.
    public static let defaultButtons: [ButtonMapping] = [
        ButtonMapping(Trigger(button: 4, kind: .click), .lookUp),
        ButtonMapping(Trigger(button: 4, kind: .scroll), .scrollDesktopAndLaunchpad),
        ButtonMapping(Trigger(button: 4, kind: .drag), .dragSpacesAndMissionControl),
        ButtonMapping(Trigger(button: 5, kind: .click), .smartZoom),
        ButtonMapping(Trigger(button: 5, kind: .scroll), .scrollZoom),
        ButtonMapping(Trigger(button: 5, kind: .drag), .dragScrollAndNavigate),
    ]
}

public enum Smoothness: String, Codable, CaseIterable, Sendable {
    case off
    case low
    case regular
    case high
}

public enum ScrollSpeed: String, Codable, CaseIterable, Sendable {
    /// Keep the distance macOS gives each tick.
    case system
    case low
    case medium
    case high
}

public struct ScrollSettings: Equatable, Sendable {
    public var smoothness = Smoothness.high
    public var trackpadSimulation = true
    public var reverse = false
    public var speed = ScrollSpeed.medium
    /// Scroll a little per tick when the wheel turns slowly, without a modifier.
    public var precision = false
    public var modifiers = ScrollModifiers()

    public init() {}
}

/// Which key, held while scrolling, switches the wheel to each mode. Nil turns the mode off.
public struct ScrollModifiers: Equatable, Sendable {
    public var horizontal: ModifierKey? = .shift
    public var zoom: ModifierKey? = .command
    public var swift: ModifierKey? = .control
    public var precise: ModifierKey? = .option

    public init() {}
}

// MARK: - Codable with defaults for missing fields

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, general, mouse
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        general = try c.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? d.general
        mouse = try c.decodeIfPresent(MouseSettings.self, forKey: .mouse) ?? d.mouse
    }
}

extension GeneralSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case showMenuBarIcon
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? Self().showMenuBarIcon
    }
}

extension MouseSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case enabled, buttons, scroll, excludedApps
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        buttons = try c.decodeIfPresent([ButtonMapping].self, forKey: .buttons) ?? d.buttons
        scroll = try c.decodeIfPresent(ScrollSettings.self, forKey: .scroll) ?? d.scroll
        excludedApps = try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? d.excludedApps
    }
}

extension ScrollSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case smoothness, trackpadSimulation, reverse, speed, precision, modifiers
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        smoothness = (try? c.decodeIfPresent(Smoothness.self, forKey: .smoothness)) ?? d.smoothness
        trackpadSimulation = try c.decodeIfPresent(Bool.self, forKey: .trackpadSimulation) ?? d.trackpadSimulation
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? d.reverse
        speed = (try? c.decodeIfPresent(ScrollSpeed.self, forKey: .speed)) ?? d.speed
        precision = try c.decodeIfPresent(Bool.self, forKey: .precision) ?? d.precision
        modifiers = try c.decodeIfPresent(ScrollModifiers.self, forKey: .modifiers) ?? d.modifiers
    }
}

extension ScrollModifiers: Codable {
    private enum CodingKeys: String, CodingKey {
        case horizontal, zoom, swift, precise
    }

    /// A key that is present with null means "off"; a missing key means "default".
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        func read(_ key: CodingKeys, _ fallback: ModifierKey?) -> ModifierKey? {
            guard c.contains(key) else { return fallback }
            return try? c.decodeIfPresent(ModifierKey.self, forKey: key)
        }
        horizontal = read(.horizontal, d.horizontal)
        zoom = read(.zoom, d.zoom)
        swift = read(.swift, d.swift)
        precise = read(.precise, d.precise)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(horizontal, forKey: .horizontal)
        try c.encode(zoom, forKey: .zoom)
        try c.encode(swift, forKey: .swift)
        try c.encode(precise, forKey: .precise)
    }
}
