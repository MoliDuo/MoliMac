import AppKit
import MoliMacCore
import SwiftUI
import UniformTypeIdentifiers

/// Apps with settings of their own. They apply to the app under the pointer.
struct AppsPage: View {
    @ObservedObject var model: AppModel
    @State private var editing: EditedApp?

    private var bundleIdentifiers: [String] {
        var seen: Set<String> = []
        let ids = model.settings.mouse.apps.map(\.bundleIdentifier) + model.settings.mouse.excludedApps
        return ids.filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section {
                if bundleIdentifiers.isEmpty {
                    Text("还没有单独设置的 App。")
                        .foregroundStyle(.secondary)
                }
                ForEach(bundleIdentifiers, id: \.self) { id in
                    row(id)
                }
            } footer: {
                SectionFooter("按指针下面的 App 生效，不一定是最前面的那个。没有单独设置的部分跟随全局设置。")
            }

            Section {
                HStack {
                    Spacer()
                    Button("添加 App…") { addApp() }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { app in
            AppSettingsSheet(model: model, bundleIdentifier: app.id)
        }
    }

    private func row(_ id: String) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: InstalledApp.icon(for: id))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(InstalledApp.name(for: id))
                Text(summary(for: id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("设置…") { editing = EditedApp(id: id) }
        }
    }

    private func summary(for id: String) -> String {
        let mouse = model.settings.mouse
        if mouse.excludedApps.contains(id) {
            return "停用鼠标模块"
        }
        let override = mouse.apps.first { $0.bundleIdentifier == id }
        var parts: [String] = []
        if override?.buttons != nil {
            parts.append("单独的按键")
        }
        if override.map({ !$0.scroll.isEmpty }) ?? false {
            parts.append("单独的滚动")
        }
        return parts.isEmpty ? "跟随全局设置" : parts.joined(separator: "、")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "添加"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else {
            return
        }
        if !bundleIdentifiers.contains(id) {
            model.settings.mouse.apps.append(AppOverride(bundleIdentifier: id))
        }
        editing = EditedApp(id: id)
    }
}

private struct EditedApp: Identifiable {
    let id: String
}

/// Name and icon of an installed app, by bundle identifier.
enum InstalledApp {
    @MainActor
    static func name(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return id
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    @MainActor
    static func icon(for id: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct AppSettingsSheet: View {
    @ObservedObject var model: AppModel
    let bundleIdentifier: String
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.general

    private enum Tab {
        case general
        case buttons
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: InstalledApp.icon(for: bundleIdentifier))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text(InstalledApp.name(for: bundleIdentifier))
                    .font(.headline)
                Spacer()
                if !isExcluded {
                    Picker("内容", selection: $tab) {
                        Text("通用").tag(Tab.general)
                        Text("按键").tag(Tab.buttons)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(16)
            Divider()

            if tab == .buttons, !isExcluded {
                buttonsTab
            } else {
                generalTab
            }

            Divider()
            HStack {
                Button("删除这个 App 的设置", role: .destructive) {
                    model.settings.mouse.apps.removeAll { $0.bundleIdentifier == bundleIdentifier }
                    model.settings.mouse.excludedApps.removeAll { $0 == bundleIdentifier }
                    dismiss()
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 580)
    }

    // MARK: - Tabs

    private var generalTab: some View {
        Form {
            Section {
                Toggle("在这个 App 里停用鼠标模块", isOn: excludedBinding)
            } footer: {
                SectionFooter("停用后，指针在这个 App 上时按键和滚轮都保持系统原来的样子。")
            }
            if !isExcluded {
                Section {
                    optionalPicker("顺滑度", scroll.smoothness, global: model.settings.mouse.scroll.smoothness.title) {
                        ForEach(Smoothness.allCases, id: \.self) { Text($0.title).tag(Smoothness?.some($0)) }
                    }
                    optionalPicker("速度", scroll.speed, global: model.settings.mouse.scroll.speed.title) {
                        ForEach(ScrollSpeed.allCases, id: \.self) { Text($0.title).tag(ScrollSpeed?.some($0)) }
                    }
                    switchPicker(
                        "模拟触控板",
                        scroll.trackpadSimulation,
                        global: model.settings.mouse.scroll.trackpadSimulation
                    )
                    switchPicker("反转方向", scroll.reverse, global: model.settings.mouse.scroll.reverse)
                    switchPicker("慢慢转时精确滚动", scroll.precision, global: model.settings.mouse.scroll.precision)
                } header: {
                    Text("滚动")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var buttonsTab: some View {
        if override.wrappedValue.buttons == nil {
            VStack(spacing: 12) {
                Text("这个 App 使用全局的按键设置。")
                    .foregroundStyle(.secondary)
                Button("为这个 App 单独设置按键") {
                    override.wrappedValue.buttons = model.settings.mouse.buttons
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ButtonsPage(model: model, list: Binding(
                    get: { override.wrappedValue.buttons ?? [] },
                    set: { override.wrappedValue.buttons = $0 }
                ))
                HStack {
                    Spacer()
                    Button("改回使用全局的按键设置") {
                        override.wrappedValue.buttons = nil
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Bindings

    private var isExcluded: Bool {
        model.settings.mouse.excludedApps.contains(bundleIdentifier)
    }

    private var excludedBinding: Binding<Bool> {
        Binding(
            get: { isExcluded },
            set: { excluded in
                model.settings.mouse.excludedApps.removeAll { $0 == bundleIdentifier }
                if excluded {
                    model.settings.mouse.excludedApps.append(bundleIdentifier)
                }
            }
        )
    }

    /// This app's override, created on first change.
    private var override: Binding<AppOverride> {
        Binding(
            get: {
                model.settings.mouse.apps.first { $0.bundleIdentifier == bundleIdentifier }
                    ?? AppOverride(bundleIdentifier: bundleIdentifier)
            },
            set: { newValue in
                if let index = model.settings.mouse.apps
                    .firstIndex(where: { $0.bundleIdentifier == bundleIdentifier })
                {
                    model.settings.mouse.apps[index] = newValue
                } else {
                    model.settings.mouse.apps.append(newValue)
                }
            }
        )
    }

    private var scroll: Binding<ScrollOverride> {
        override.scroll
    }

    private func optionalPicker<Value: Hashable>(
        _ title: String,
        _ selection: Binding<Value?>,
        global: String,
        @ViewBuilder options: () -> some View
    ) -> some View {
        Picker(title, selection: selection) {
            Text("跟随全局（" + global + "）").tag(Value?.none)
            Divider()
            options()
        }
    }

    private func switchPicker(_ title: String, _ selection: Binding<Bool?>, global: Bool) -> some View {
        optionalPicker(title, selection, global: global ? "开" : "关") {
            Text("开").tag(Bool?.some(true))
            Text("关").tag(Bool?.some(false))
        }
    }
}
