import Foundation

enum AppInfo {
    /// Display name (MoliSpec 001).
    static let name = "Moli Mac"
    static let repositoryURL = URL(string: "https://github.com/MoliDuo/MoliMac")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else {
            return "开发版本"
        }
        return version
    }

    /// Bundle identifiers of Mac Mouse Fix and its helper. Both apps intercepting the
    /// same mouse events would do every action twice.
    static let macMouseFixBundleIdentifiers: Set<String> = [
        "com.nuebling.mac-mouse-fix",
        "com.nuebling.mac-mouse-fix.helper",
    ]
}
