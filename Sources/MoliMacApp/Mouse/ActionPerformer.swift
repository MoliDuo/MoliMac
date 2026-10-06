import AppKit
import CoreGraphics
import MoliMacCore

/// Performs the actions that happen once, on a click or when a hold starts.
/// Runs on the event tap thread.
enum ActionPerformer {
    static func perform(_ action: MouseAction) {
        Log.actions.debug("perform \(String(describing: action), privacy: .public)")
        if action == .lookUp, AppUnderPointer.bundleIdentifier() == "com.apple.finder" {
            // Look Up does nothing useful on files; Quick Look (space) does.
            SyntheticEvents.postKey(49, flags: [])
            return
        }
        if let hotKey = SymbolicHotKey(action: action) {
            SymbolicHotKeys.post(hotKey)
            return
        }
        switch action {
        case .back:
            navigate(forward: false)
        case .forward:
            navigate(forward: true)
        case .middleClick:
            SyntheticEvents.postClicks(button: 3, count: 1)
        case let .keyboardShortcut(shortcut):
            SyntheticEvents.post(shortcut)
        case .smartZoom:
            GestureEvents.postSmartZoom()
        default:
            Log.actions.error("not an instant action: \(String(describing: action), privacy: .public)")
        }
    }

    private static func navigate(forward: Bool) {
        switch NavigationMethod.forApp(bundleIdentifier: AppUnderPointer.bundleIdentifier()) {
        case .swipe:
            GestureEvents.postNavigationSwipe(back: !forward)
        case .mouseButtons:
            SyntheticEvents.postClicks(button: forward ? 5 : 4, count: 1)
        case let .keys(back, forwardKeys):
            SyntheticEvents.post(forward ? forwardKeys : back)
        }
    }
}

/// `AppUnderPointer` with the answer kept for a moment, since it is asked on every
/// wheel tick and listing windows takes a millisecond or two.
struct AppUnderPointerCache {
    private static let lifetime = 0.3
    private var time = -Double.infinity
    private var value: String?

    mutating func bundleIdentifier() -> String? {
        let now = ProcessInfo.processInfo.systemUptime
        if now - time > Self.lifetime {
            value = AppUnderPointer.bundleIdentifier()
            time = now
        }
        return value
    }
}

/// The app that owns the window under the pointer, which is the one the user means
/// even when another app is in front.
enum AppUnderPointer {
    static func bundleIdentifier() -> String? {
        let location = CGEvent(source: nil)?.location ?? .zero
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard
                let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                bounds.contains(location)
            else {
                continue
            }
            return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
