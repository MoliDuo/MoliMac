import MoliMacCore
import SwiftUI

struct ScrollPage: View {
    @ObservedObject var model: AppModel

    private var scroll: Binding<ScrollSettings> {
        $model.settings.mouse.scroll
    }

    var body: some View {
        Form {
            Section {
                Picker("顺滑度", selection: scroll.smoothness) {
                    ForEach(Smoothness.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("模拟触控板", isOn: scroll.trackpadSimulation)
                Picker("速度", selection: scroll.speed) {
                    ForEach(ScrollSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("反转方向", isOn: scroll.reverse)
                Toggle("慢慢转时精确滚动", isOn: scroll.precision)
            } header: {
                Text("滚轮")
            } footer: {
                SectionFooter(
                    "模拟触控板后，Safari 等 App 会有回弹效果，横向滚到头可以翻页。只影响鼠标滚轮，触控板和妙控鼠标不受影响。"
                )
            }

            Section {
                modifierPicker("横向滚动", \.horizontal)
                modifierPicker("缩放", \.zoom)
                modifierPicker("快速滚动", \.swift)
                modifierPicker("精确滚动", \.precise)
            } header: {
                Text("滚动时按住")
            } footer: {
                if hasDuplicateModifiers {
                    NoticeRow(text: "有几项用了同一个键，按住时会互相影响。")
                } else {
                    SectionFooter("快速滚动每格大约滚半屏到一屏半，精确滚动每格只滚几个像素。")
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("恢复默认") {
                        model.settings.mouse.scroll = ScrollSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func modifierPicker(
        _ title: String,
        _ keyPath: WritableKeyPath<ScrollModifiers, ModifierKey?>
    ) -> some View {
        Picker(title, selection: scroll.modifiers[dynamicMember: keyPath]) {
            Text("不使用").tag(ModifierKey?.none)
            Divider()
            ForEach(ModifierKey.allCases, id: \.self) { key in
                Text(key.title).tag(ModifierKey?.some(key))
            }
        }
    }

    private var hasDuplicateModifiers: Bool {
        let modifiers = model.settings.mouse.scroll.modifiers
        let used = [modifiers.horizontal, modifiers.zoom, modifiers.swift, modifiers.precise].compactMap(\.self)
        return Set(used).count != used.count
    }
}

extension Smoothness {
    var title: String {
        switch self {
        case .off: "关闭"
        case .low: "低"
        case .regular: "标准"
        case .high: "高"
        }
    }
}

extension ScrollSpeed {
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

extension ModifierKey {
    var title: String {
        switch self {
        case .control: "⌃ Control"
        case .option: "⌥ Option"
        case .shift: "⇧ Shift"
        case .command: "⌘ Command"
        }
    }
}
