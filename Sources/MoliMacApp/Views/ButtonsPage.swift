import AppKit
import MoliMacCore
import SwiftUI

struct ButtonsPage: View {
    @ObservedObject var model: AppModel
    /// The list to edit; the global one when nil.
    var list: Binding<[ButtonMapping]>?
    @State private var captureMessage: String?
    @State private var recording: RecordingTarget?

    private var buttons: Binding<[ButtonMapping]> {
        list ?? $model.settings.mouse.buttons
    }

    private var mappings: [ButtonMapping] {
        buttons.wrappedValue
    }

    var body: some View {
        Form {
            Section {
                captureArea
            } footer: {
                SectionFooter(captureMessage ?? "把指针移到上面的区域里，按一下要设置的鼠标按键。左键和右键不能改。")
            }

            ForEach(ButtonList.buttons(in: mappings), id: \.self) { button in
                Section {
                    ForEach(ButtonList.mappings(for: button, in: mappings), id: \.trigger) { mapping in
                        row(mapping)
                    }
                } header: {
                    header(button)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("恢复默认…") { confirmRestoreDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { model.mouse.setCapturing(false) }
        .sheet(item: $recording) { target in
            ShortcutRecorder { shortcut in
                if let shortcut {
                    ButtonList.setAction(
                        .keyboardShortcut(shortcut),
                        for: target.trigger,
                        in: &buttons.wrappedValue
                    )
                }
                recording = nil
            }
        }
    }

    // MARK: - Capture area

    private var captureArea: some View {
        ZStack {
            ButtonCaptureView { button in
                captured(button)
            }
            VStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.title)
                Text("在这里按下鼠标按键")
            }
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
        }
        .frame(height: 84)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4]))
        }
        // Remapped buttons are taken over before they reach any window, so the
        // engine lets everything through while the pointer is over the area.
        .onHover { model.mouse.setCapturing($0) }
    }

    private func captured(_ button: Int) {
        let name = ButtonName.title(button)
        if !RemapTable.remappableButtons.contains(button) {
            captureMessage = name + "不能改。"
        } else if ButtonList.addButton(button, to: &buttons.wrappedValue) {
            captureMessage = "已添加" + name + "，在下面选择它的动作。"
        } else {
            captureMessage = name + "已经在下面了。"
        }
    }

    // MARK: - Rows

    private func header(_ button: Int) -> some View {
        let unused = ButtonList.unusedTriggers(for: button, in: mappings)
        return HStack {
            Text(ButtonName.title(button))
            Spacer()
            Menu {
                ForEach(unused, id: \.self) { trigger in
                    Button(trigger.title) {
                        ButtonList.add(trigger, to: &buttons.wrappedValue)
                    }
                }
            } label: {
                Label("添加按法", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(unused.isEmpty)
        }
    }

    private func row(_ mapping: ButtonMapping) -> some View {
        let trigger = mapping.trigger
        let choices = MouseAction.choices(for: trigger.kind)
        return LabeledContent(trigger.title) {
            HStack(spacing: 8) {
                Picker("动作", selection: actionBinding(for: trigger)) {
                    Text(MouseAction.none.title).tag(MouseAction.none)
                    Divider()
                    ForEach(choices, id: \.self) { action in
                        Text(action.title).tag(action)
                    }
                    if mapping.action != .none, !choices.contains(mapping.action) {
                        Divider()
                        Text(mapping.action.title).tag(mapping.action)
                    }
                }
                .labelsHidden()
                .fixedSize()

                if trigger.kind.actionKind == .instant {
                    Button("快捷键…") { recording = RecordingTarget(trigger: trigger) }
                }

                Button {
                    ButtonList.remove(trigger, from: &buttons.wrappedValue)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("删除这一行")
                .accessibilityLabel("删除" + trigger.title)
            }
        }
    }

    private func actionBinding(for trigger: Trigger) -> Binding<MouseAction> {
        Binding(
            get: { buttons.wrappedValue.first { $0.trigger == trigger }?.action ?? .none },
            set: { ButtonList.setAction($0, for: trigger, in: &buttons.wrappedValue) }
        )
    }

    private func confirmRestoreDefaults() {
        let alert = NSAlert()
        alert.messageText = "恢复默认的按键设置？"
        alert.informativeText = "这一页的所有改动都会被替换成默认设置。"
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            buttons.wrappedValue = MouseSettings.defaultButtons
            captureMessage = nil
        }
    }
}

private struct RecordingTarget: Identifiable {
    let trigger: Trigger

    var id: Trigger {
        trigger
    }
}

/// Reports the number of any mouse button pressed over it (1 = left).
private struct ButtonCaptureView: NSViewRepresentable {
    let onButton: (Int) -> Void

    func makeNSView(context _: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onButton = onButton
        return view
    }

    func updateNSView(_ view: CaptureNSView, context _: Context) {
        view.onButton = onButton
    }

    final class CaptureNSView: NSView {
        var onButton: ((Int) -> Void)?

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            onButton?(event.buttonNumber + 1)
        }

        override func rightMouseDown(with event: NSEvent) {
            onButton?(event.buttonNumber + 1)
        }

        override func otherMouseDown(with event: NSEvent) {
            onButton?(event.buttonNumber + 1)
        }
    }
}

/// Waits for one key press and reports it as a shortcut; Esc cancels.
private struct ShortcutRecorder: View {
    let onFinish: (MoliMacCore.KeyboardShortcut?) -> Void
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("按下要发送的快捷键")
                .font(.headline)
            Text("按 Esc 取消。")
                .foregroundStyle(.secondary)
            Button("取消") { onFinish(nil) }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                record(event)
                return nil
            }
        }
        .onDisappear {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<ModifierKey> = []
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if event.keyCode == 53, modifiers.isEmpty {
            onFinish(nil)
        } else {
            onFinish(MoliMacCore.KeyboardShortcut(keyCode: event.keyCode, modifiers: modifiers))
        }
    }
}
