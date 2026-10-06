import AppKit

/// Process entry point.
///
/// The app code lives in a library target so tests can reach it without a second
/// main entry point. The executable target only calls this function.
@MainActor
public enum ApplicationEntryPoint {
    /// NSApplication does not retain its delegate, so it is kept alive here.
    private static var delegate: AppDelegate?

    public static func run() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        application.delegate = appDelegate
        application.run()
    }
}
