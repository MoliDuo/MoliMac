import SwiftUI

struct GeneralPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("鼠标", isOn: $model.isMouseEnabled)
            } header: {
                Text("功能")
            } footer: {
                SectionFooter("关闭后，鼠标的按键和滚轮恢复系统原来的样子。")
            }

            Section {
                Toggle(
                    "登录时打开",
                    isOn: Binding(
                        get: { model.isLaunchAtLoginEnabled },
                        set: { model.setLaunchAtLoginEnabled($0) }
                    )
                )
                if model.launchAtLoginStatus == .requiresApproval {
                    NoticeRow(text: "需要在系统设置中允许。") {
                        Button("打开系统设置…") { LoginItem.openSystemSettings() }
                    }
                }
                if let failure = model.launchAtLoginFailure {
                    NoticeRow(text: "无法更改登录项：" + failure, severity: .error)
                }
                Toggle("在菜单栏中显示图标", isOn: $model.settings.general.showMenuBarIcon)
            } header: {
                Text("启动")
            } footer: {
                if !model.settings.general.showMenuBarIcon {
                    SectionFooter("图标隐藏后，再次打开 " + AppInfo.name + " 即可回到这个窗口。")
                }
            }

            Section("权限") {
                LabeledContent("辅助功能") {
                    if model.accessibility.isTrusted {
                        Label("已允许", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("打开系统设置…") {
                            model.accessibility.prompt()
                            model.accessibility.openSystemSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
