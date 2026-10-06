import MoliMacCore
import SwiftUI

struct PointerPage: View {
    @ObservedObject var model: AppModel

    private var pointer: Binding<PointerSettings> {
        $model.settings.mouse.pointer
    }

    var body: some View {
        Form {
            Section {
                Picker("指针加速", selection: pointer.acceleration) {
                    Text("跟随系统").tag(Bool?.none)
                    Divider()
                    Text("开启").tag(Bool?.some(true))
                    Text("关闭").tag(Bool?.some(false))
                }
                Toggle("调节指针速度", isOn: Binding(
                    get: { model.settings.mouse.pointer.speed != nil },
                    set: { model.settings.mouse.pointer.speed = $0 ? 1 : nil }
                ))
                if let speed = model.settings.mouse.pointer.speed {
                    LabeledContent("速度") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { speed },
                                    set: { model.settings.mouse.pointer.speed = ($0 * 10).rounded() / 10 }
                                ),
                                in: PointerSettings.speedRange,
                                step: 0.1
                            ) {
                                Text("速度")
                            } minimumValueLabel: {
                                Text("慢")
                            } maximumValueLabel: {
                                Text("快")
                            }
                            .labelsHidden()
                            Text(speed.formatted(.number.precision(.fractionLength(1))) + " 倍")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            } footer: {
                SectionFooter(
                    "关闭加速后，指针移动的距离只跟鼠标移动的距离成正比。只影响鼠标，不影响触控板；关闭鼠标模块或退出 "
                        + AppInfo.name + " 时恢复系统设置。"
                )
            }
        }
        .formStyle(.grouped)
    }
}
