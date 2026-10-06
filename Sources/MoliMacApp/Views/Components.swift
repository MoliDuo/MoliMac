import SwiftUI

enum NoticeSeverity {
    case warning
    case error
}

/// A warning or error with the actions that resolve it.
struct NoticeRow<Actions: View>: View {
    let text: String
    var severity = NoticeSeverity.warning
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(severity == .error ? .red : .orange)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actions
        }
    }
}

extension NoticeRow where Actions == EmptyView {
    init(text: String, severity: NoticeSeverity = .warning) {
        self.init(text: text, severity: severity) { EmptyView() }
    }
}

/// Separate view so the button observes the updater directly.
struct CheckForUpdatesButton: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        Button("检查更新…") {
            controller.checkForUpdates()
        }
        .disabled(!controller.canCheckForUpdates)
    }
}

/// Explanatory text under a form section, leading-aligned like the rows above it.
struct SectionFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
