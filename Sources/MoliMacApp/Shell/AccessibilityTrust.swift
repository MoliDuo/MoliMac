import AppKit
import ApplicationServices

/// Watches the Accessibility permission, which event taps need.
///
/// macOS sends no notification when the permission changes. It is polled once a
/// second: when it is revoked while taps are running the system stops delivering
/// events to them, and the taps have to be removed at once or the mouse stalls.
@MainActor
final class AccessibilityTrust: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    /// Shows the system prompt that adds the app to the Accessibility list.
    func prompt() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
