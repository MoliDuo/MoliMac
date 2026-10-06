import SwiftUI

struct AboutPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: AppInfo.version)
                    .monospacedDigit()
                if let controller = model.updateController {
                    HStack {
                        Spacer()
                        CheckForUpdatesButton(controller: controller)
                    }
                }
            }

            Section {
                Link("在 GitHub 上查看", destination: AppInfo.repositoryURL)
            } footer: {
                SectionFooter(
                    "鼠标功能参照 Mac Mouse Fix（Noah Nuebling）的设计实现，感谢它多年来对 macOS 鼠标体验的探索。"
                )
            }
        }
        .formStyle(.grouped)
    }
}
