import Foundation

/// Reads and writes `settings.json`.
///
/// - A missing file means defaults.
/// - A file that cannot be read is never overwritten: the app runs on defaults and
///   says so, and only an explicit reset moves the broken file aside.
/// - Writing keeps every field of the existing file that this version does not
///   model, so a newer version's settings survive a round trip through an older one.
public final class SettingsStore: @unchecked Sendable {
    public enum LoadResult: Sendable {
        case loaded(AppSettings)
        case missing
        case unreadable(String)
    }

    public enum StoreError: Error, CustomStringConvertible {
        case unreadableFileNotReset
        case writeFailed(String)

        public var description: String {
            switch self {
            case .unreadableFileNotReset:
                "设置文件无法读取，先恢复默认设置再保存"
            case let .writeFailed(reason):
                "无法保存设置：" + reason
            }
        }
    }

    public let url: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    /// The file as last read, used to keep unknown fields. Nil when there was no file.
    private var lastRaw: Any?
    private var isUnreadable = false

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public static func applicationSupportDirectory(appName: String = "MoliMac") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public static func standard() -> SettingsStore {
        SettingsStore(url: applicationSupportDirectory().appendingPathComponent("settings.json"))
    }

    public func load() -> LoadResult {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: url.path) else {
            lastRaw = nil
            isUnreadable = false
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONSerialization.jsonObject(with: data)
            guard raw is [String: Any] else {
                throw DecodingError.typeMismatch(
                    [String: Any].self,
                    .init(codingPath: [], debugDescription: "顶层不是对象")
                )
            }
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            lastRaw = raw
            isUnreadable = false
            return .loaded(settings)
        } catch {
            isUnreadable = true
            return .unreadable(Self.describe(error))
        }
    }

    public func save(_ settings: AppSettings) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !isUnreadable else {
            throw StoreError.unreadableFileNotReset
        }
        try write(settings)
    }

    /// Moves an unreadable file aside (so nothing is lost) and writes defaults.
    /// - Returns: where the old file went, if there was one.
    @discardableResult
    public func resetToDefaults() throws -> URL? {
        lock.lock()
        defer { lock.unlock() }

        var backup: URL?
        if isUnreadable, fileManager.fileExists(atPath: url.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let target = url.deletingPathExtension().appendingPathExtension("broken-\(stamp).json")
            do {
                try fileManager.moveItem(at: url, to: target)
            } catch {
                throw StoreError.writeFailed(error.localizedDescription)
            }
            backup = target
        }
        isUnreadable = false
        lastRaw = nil
        try write(AppSettings())
        return backup
    }

    private func write(_ settings: AppSettings) throws {
        do {
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
            let merged = lastRaw.map { JSONMerge.merge(base: $0, overlay: encoded) } ?? encoded
            let data = try JSONSerialization.data(
                withJSONObject: merged,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastRaw = merged
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case let DecodingError.dataCorrupted(context),
             let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context),
             let DecodingError.keyNotFound(_, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : path + "：" + context.debugDescription
        default:
            return error.localizedDescription
        }
    }
}

/// Deep merge of JSON values: objects merge key by key, anything else is replaced.
enum JSONMerge {
    static func merge(base: Any, overlay: Any) -> Any {
        guard let baseObject = base as? [String: Any], let overlayObject = overlay as? [String: Any] else {
            return overlay
        }
        var result = baseObject
        for (key, value) in overlayObject {
            result[key] = result[key].map { merge(base: $0, overlay: value) } ?? value
        }
        return result
    }
}
