import AppKit
import MoliMacCore

/// Turns the mouse engine on and off from the main thread.
///
/// The tap runs only while the module is on, the app has the Accessibility
/// permission and the Mac is awake. Losing any of them removes it at once, so the
/// mouse never ends up with a tap the system has stopped feeding.
@MainActor
final class MouseModule {
    private let thread = EventTapThread()
    private let engine: MouseEngine
    private var settings = MouseSettings()
    private var isTrusted = false
    private var isAwake = true
    private var observers: [any NSObjectProtocol] = []

    init() {
        thread.startAndWait()
        engine = MouseEngine(thread: thread, clock: FrameClock(thread: thread))
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let sleepEvents: [(Notification.Name, Bool)] = [
            (NSWorkspace.willSleepNotification, false),
            (NSWorkspace.didWakeNotification, true),
        ]
        for (name, awake) in sleepEvents {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isAwake = awake
                    self?.apply()
                }
            })
        }
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        let engine = engine
        let done = DispatchSemaphore(value: 0)
        thread.perform {
            engine.configure(MouseEngine.Configuration())
            done.signal()
        }
        // Wait briefly so the tap is gone before the process exits.
        _ = done.wait(timeout: .now() + 1)
    }

    func update(settings: MouseSettings, isTrusted: Bool) {
        self.settings = settings
        self.isTrusted = isTrusted
        apply()
    }

    /// Lets every event through while the settings page waits for a button press.
    func setCapturing(_ capturing: Bool) {
        let engine = engine
        thread.perform {
            engine.setBypass(capturing)
        }
    }

    private func apply() {
        let configuration = MouseEngine.Configuration(
            table: RemapTable(settings.buttons),
            scroll: settings.scroll,
            screenHeight: Double(NSScreen.main?.frame.height ?? 1000),
            active: settings.enabled && isTrusted && isAwake
        )
        let engine = engine
        thread.perform {
            engine.configure(configuration)
        }
    }
}
