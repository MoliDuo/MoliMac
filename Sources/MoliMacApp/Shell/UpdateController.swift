import AppKit
import Combine
import Sparkle

/// Thin wrapper around Sparkle's standard updater (MoliSpec 007 §7.4).
///
/// Sparkle already keeps the two cases apart: a check the user starts shows progress,
/// "up to date" and any failure; the hourly background check stays quiet unless an
/// update is available. Bundles without a feed URL and a usable public key, such as
/// `swift run` builds, never start an updater that could only fail.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let hostBundle: Bundle
    private var observation: NSKeyValueObservation?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private init(hostBundle: Bundle) {
        self.hostBundle = hostBundle
        super.init()
    }

    static func makeForHostBundle(_ bundle: Bundle = .main) -> UpdateController? {
        guard isConfigured(bundle) else {
            return nil
        }
        return UpdateController(hostBundle: bundle)
    }

    static func isConfigured(_ bundle: Bundle) -> Bool {
        guard
            let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let url = URL(string: feed.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https",
            let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else {
            return false
        }
        // An Ed25519 public key is 32 bytes.
        return Data(base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines))?.count == 32
    }

    func start() {
        let updater = updaterController.updater
        canCheckForUpdates = updater.canCheckForUpdates
        // KVO calls back on whichever thread changed the value; hop to the main actor.
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                canCheckForUpdates = updaterController.updater.canCheckForUpdates
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }

    /// Why an update cannot be installed from where the app runs (MoliSpec 7.4.5).
    private var blockingReason: String? {
        let path = hostBundle.bundlePath
        if path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") {
            return "请先把 " + AppInfo.name + " 移到「应用程序」文件夹，再检查更新。"
        }
        return nil
    }

    func checkForUpdates() {
        if let reason = blockingReason {
            let alert = NSAlert()
            alert.messageText = "无法更新"
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            NSApp.activate()
            alert.runModal()
            return
        }
        updaterController.updater.checkForUpdates()
    }
}
