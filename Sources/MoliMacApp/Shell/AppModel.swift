import AppKit
import Combine
import MoliMacCore

/// State shared by the menu bar item and the settings window.
@MainActor
final class AppModel: ObservableObject {
    /// The settings in use. Changing them saves the file, unless the file on disk
    /// could not be read: then changes apply but are not saved until the user resets.
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }

    /// Why the settings file could not be read, while the app runs on defaults.
    @Published private(set) var settingsReadFailure: String?
    @Published private(set) var settingsSaveFailure: String?
    @Published private(set) var launchAtLoginStatus = LoginItem.status
    @Published private(set) var launchAtLoginFailure: String?

    let store: SettingsStore
    let accessibility = AccessibilityTrust()
    let macMouseFix = MacMouseFixWatcher()
    let mouse = MouseModule()
    let updateController: UpdateController?

    private var cancellables: Set<AnyCancellable> = []

    init(store: SettingsStore, updateController: UpdateController?) {
        self.store = store
        self.updateController = updateController
        switch store.load() {
        case let .loaded(loaded):
            settings = loaded
        case .missing:
            settings = AppSettings()
        case let .unreadable(reason):
            settings = AppSettings()
            settingsReadFailure = reason
            Log.app.error("settings unreadable: \(reason, privacy: .public)")
        }

        // Nested observable objects do not republish on their own.
        for publisher in [accessibility.objectWillChange, macMouseFix.objectWillChange] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
        updateController?.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        accessibility.start()
        macMouseFix.start()
        mouse.start()
        Publishers.CombineLatest($settings.map(\.mouse).removeDuplicates(), accessibility.$isTrusted.removeDuplicates())
            .sink { [weak self] mouse, isTrusted in
                self?.mouse.update(settings: mouse, isTrusted: isTrusted)
            }
            .store(in: &cancellables)
        updateController?.start()
    }

    func stop() {
        mouse.stop()
        accessibility.stop()
        macMouseFix.stop()
        updateController?.stop()
    }

    // MARK: - Settings file

    private func save() {
        guard settingsReadFailure == nil else {
            return
        }
        do {
            try store.save(settings)
            settingsSaveFailure = nil
        } catch {
            settingsSaveFailure = String(describing: error)
            Log.app.error("settings save failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Moves the unreadable file aside and saves the settings in use.
    func resetUnreadableSettings() {
        do {
            let backup = try store.resetToDefaults()
            settingsReadFailure = nil
            if let backup {
                Log.app.info("moved unreadable settings to \(backup.path, privacy: .public)")
            }
            save()
        } catch {
            settingsSaveFailure = String(describing: error)
        }
    }

    func reloadSettings() {
        switch store.load() {
        case let .loaded(loaded):
            settingsReadFailure = nil
            settings = loaded
        case .missing:
            settingsReadFailure = nil
        case let .unreadable(reason):
            settingsReadFailure = reason
        }
    }

    func revealSettingsFile() {
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    // MARK: - Launch at login

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginStatus.isRegistered
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            launchAtLoginFailure = nil
        } catch {
            launchAtLoginFailure = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        launchAtLoginStatus = LoginItem.status
    }

    // MARK: - Mouse module

    var isMouseEnabled: Bool {
        get { settings.mouse.enabled }
        set { settings.mouse.enabled = newValue }
    }
}
