import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case general
    case buttons
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "通用"
        case .buttons: "按键"
        case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .buttons: "computermouse"
        case .about: "info.circle"
        }
    }
}

struct SettingsWindowView: View {
    @ObservedObject var model: AppModel
    @AppStorage("selectedSidebarItem") private var selection = SidebarItem.general

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    sidebarRow(.general)
                }
                Section("鼠标") {
                    sidebarRow(.buttons)
                }
                Section {
                    sidebarRow(.about)
                }
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            detail
                .navigationTitle(selection.title)
                .safeAreaInset(edge: .top, spacing: 0) {
                    notices
                }
        }
        .tint(Theme.accent)
        .frame(minWidth: 680, minHeight: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may come back from System Settings having changed something.
            model.accessibility.refresh()
            model.refreshLaunchAtLogin()
        }
    }

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralPage(model: model)
        case .buttons:
            ButtonsPage(model: model)
        case .about:
            AboutPage(model: model)
        }
    }

    /// Problems that need the user, shown on every page.
    @ViewBuilder
    private var notices: some View {
        let needsAccessibility = model.isMouseEnabled && !model.accessibility.isTrusted
        let showsMacMouseFix = model.isMouseEnabled && model.macMouseFix.isRunning
        let readFailure = model.settingsReadFailure
        let saveFailure = model.settingsSaveFailure

        if needsAccessibility || showsMacMouseFix || readFailure != nil || saveFailure != nil {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if let readFailure {
                        NoticeRow(
                            text: "设置文件无法读取，正在使用默认设置，改动不会保存。原文件未修改。（" + readFailure + "）",
                            severity: .error
                        ) {
                            Button("重新读取") { model.reloadSettings() }
                            Button("在 Finder 中显示") { model.revealSettingsFile() }
                            Button("恢复默认…") { confirmReset() }
                        }
                    } else if let saveFailure {
                        NoticeRow(text: saveFailure, severity: .error)
                    }
                    if needsAccessibility {
                        NoticeRow(text: "需要「辅助功能」权限才能接管鼠标按键和滚轮。") {
                            Button("打开系统设置…") {
                                model.accessibility.prompt()
                                model.accessibility.openSystemSettings()
                            }
                        }
                    }
                    if showsMacMouseFix {
                        NoticeRow(text: "Mac Mouse Fix 正在运行，两个同时运行会让每个动作执行两次。") {
                            Button("退出 Mac Mouse Fix") { model.macMouseFix.quit() }
                        }
                    }
                }
                .font(.callout)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                Divider()
            }
            .background(.bar)
        }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "恢复默认设置？"
        alert.informativeText = "无法读取的设置文件会改名保留在原来的文件夹里，然后用默认设置重新开始。"
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.resetUnreadableSettings()
        }
    }
}
