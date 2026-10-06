import AppKit
import Combine
import MoliMacCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation {
    private static let windowFrameName = "SettingsWindow"
    /// Launches this soon after boot with launch at login on count as login launches
    /// when the system did not mark them as such.
    private static let loginLaunchUptimeLimit: TimeInterval = 180

    private let store: SettingsStore
    private let coordinator: SingleInstanceCoordinator

    private var model: AppModel?
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var launchedAsLoginItem = false

    init(store: SettingsStore = .standard()) {
        self.store = store
        coordinator = SingleInstanceCoordinator(
            lock: SingleInstanceLock(
                url: store.url.deletingLastPathComponent().appendingPathComponent("instance.lock")
            )
        )
        super.init()
    }

    // MARK: - Launch

    func applicationWillFinishLaunching(_: Notification) {
        // The launch event is only available until launching finishes.
        launchedAsLoginItem = Self.launchEventIsLoginItem()
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard claimSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        let model = AppModel(store: store, updateController: UpdateController.makeForHostBundle())
        self.model = model

        NSApp.mainMenu = makeMainMenu()
        setupStatusItem(visible: model.settings.general.showMenuBarIcon)
        model.$settings
            .map(\.general.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.statusItem?.isVisible = visible
            }
            .store(in: &cancellables)

        model.start()
        coordinator.startRespondingToShowRequests { [weak self] in
            self?.showWindow()
        }

        // Opening the app shows the window. A launch at login stays in the menu bar,
        // unless something needs the user.
        let isLoginLaunch = launchedAsLoginItem
            || (model.isLaunchAtLoginEnabled && ProcessInfo.processInfo.systemUptime < Self.loginLaunchUptimeLimit)
        let needsUser = model.settingsReadFailure != nil
            || (model.isMouseEnabled && !model.accessibility.isTrusted)
        if !isLoginLaunch || needsUser {
            showWindow()
        }
        Log.app.info("launched \(AppInfo.version, privacy: .public)")
    }

    private static func launchEventIsLoginItem() -> Bool {
        guard
            let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventID == AEEventID(kAEOpenApplication)
        else {
            return false
        }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }

    private func claimSingleInstance() -> Bool {
        do {
            if try coordinator.acquireExclusiveInstance() {
                return true
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法启动 " + AppInfo.name
            alert.informativeText = String(describing: error)
            alert.alertStyle = .critical
            alert.addButton(withTitle: "退出")
            alert.runModal()
            return false
        }
        // Another instance holds the lock. Ask it to show its window and exit even
        // without an answer: a second set of event taps must never start.
        coordinator.requestShowFromExistingInstance()
        return false
    }

    // MARK: - Window

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_: Notification) {
        cancellables.removeAll()
        model?.stop()
        coordinator.releaseLock()
    }

    func showWindow() {
        if window == nil, let model {
            let controller = NSHostingController(rootView: SettingsWindowView(model: model))
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.title = AppInfo.name
            window.toolbarStyle = .unified
            window.contentMinSize = NSSize(width: 680, height: 460)
            window.setContentSize(NSSize(width: 760, height: 520))
            if !window.setFrameUsingName(Self.windowFrameName) {
                window.center()
            }
            window.setFrameAutosaveName(Self.windowFrameName)
            window.delegate = self
            window.isReleasedWhenClosed = false
            self.window = window
        }
        guard let window else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Main menu

    /// An accessory app shows no menu bar, but its main menu still handles standard
    /// key equivalents such as ⌘W, ⌘Q and ⌘V in text fields.
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: AppInfo.name)
        appMenu.addItem(makeMenuItem(title: "设置…", action: #selector(showWindowFromMenu), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "隐藏 " + AppInfo.name,
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "退出 " + AppInfo.name,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        addSubmenu(appMenu, to: mainMenu)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        addSubmenu(editMenu, to: mainMenu)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(
            title: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        addSubmenu(windowMenu, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    // MARK: - Status item

    private func setupStatusItem(visible: Bool) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.image()
        item.button?.toolTip = AppInfo.name
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = visible
        statusItem = item
    }

    /// Rebuilt each time it opens, so the pause item shows the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else {
            return
        }
        menu.removeAllItems()
        menu.addItem(makeMenuItem(title: "打开设置…", action: #selector(showWindowFromMenu), keyEquivalent: ","))
        menu.addItem(.separator())
        let pause = makeMenuItem(title: "暂停鼠标模块", action: #selector(toggleMousePaused))
        pause.state = (model?.isMouseEnabled ?? true) ? .off : .on
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "检查更新…", action: #selector(checkForUpdatesFromMenu)))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "退出 " + AppInfo.name, action: #selector(terminateApp), keyEquivalent: "q"))
    }

    /// Targets are set explicitly so the actions never depend on the responder chain.
    private func makeMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdatesFromMenu) {
            return model?.updateController?.canCheckForUpdates ?? false
        }
        return true
    }

    @objc private func showWindowFromMenu() {
        showWindow()
    }

    @objc private func toggleMousePaused() {
        model?.isMouseEnabled.toggle()
    }

    @objc private func checkForUpdatesFromMenu() {
        model?.updateController?.checkForUpdates()
    }

    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }
}
