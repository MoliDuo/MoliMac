import AppKit
import CoreGraphics
import MoliMacCore

/// Performs the actions that happen once, on a click or when a hold starts.
/// Runs on the event tap thread.
enum ActionPerformer {
    static func perform(_ action: MouseAction) {
        Log.actions.debug("perform \(String(describing: action), privacy: .public)")
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
            // Needs the trackpad gesture events, which are not posted yet.
            Log.actions.info("smart zoom is not available yet")
        default:
            Log.actions.error("not an instant action: \(String(describing: action), privacy: .public)")
        }
    }

    private static func navigate(forward: Bool) {
        var method = NavigationMethod.forApp(bundleIdentifier: AppUnderPointer.bundleIdentifier())
        if method == .swipe {
            // The swipe gesture is not posted yet; Apple's apps also accept ⌘[ and ⌘].
            method = .commandBrackets
        }
        switch method {
        case .swipe, .mouseButtons:
            SyntheticEvents.postClicks(button: forward ? 5 : 4, count: 1)
        case let .keys(back, forwardKeys):
            SyntheticEvents.post(forward ? forwardKeys : back)
        }
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
