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
    private let pointer = PointerController()
    private let autoscrollIndicator = AutoscrollIndicator()
    private var settings = MouseSettings()
    private var isTrusted = false
    private var isAwake = true
    private var observers: [any NSObjectProtocol] = []

    init() {
        thread.startAndWait()
        engine = MouseEngine(thread: thread, clock: FrameClock(thread: thread))
        let engine = engine
        let indicator = UncheckedBox(autoscrollIndicator)
        thread.perform {
            engine.setAutoscrollObserver { point in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        indicator.value.show(at: point)
                    }
                }
            }
        }
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
        pointer.restoreAll()
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
        let active = settings.enabled && isTrusted && isAwake
        pointer.update(settings.pointer, active: settings.enabled && isAwake)
        let configuration = MouseEngine.Configuration(
            settings: settings,
            screenHeight: Double(NSScreen.main?.frame.height ?? 1000),
            active: active
        )
        let engine = engine
        thread.perform {
            engine.configure(configuration)
        }
    }
}
