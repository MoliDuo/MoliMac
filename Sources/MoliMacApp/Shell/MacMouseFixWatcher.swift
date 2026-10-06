import AppKit

/// Tells whether Mac Mouse Fix is running. With both running, each button press and
/// wheel tick would be handled twice.
@MainActor
final class MacMouseFixWatcher: ObservableObject {
    @Published private(set) var isRunning = false

    private var observers: [any NSObjectProtocol] = []

    func start() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            })
        }
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
    }

    private func refresh() {
        isRunning = !runningApplications().isEmpty
    }

    private func runningApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier.map(AppInfo.macMouseFixBundleIdentifiers.contains) ?? false
        }
    }

    /// Quits Mac Mouse Fix and its helper. The helper is a login item and comes back
    /// at the next login unless the user turns it off in Mac Mouse Fix.
    func quit() {
        for application in runningApplications() {
            application.terminate()
        }
    }
}
