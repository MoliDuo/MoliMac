import Foundation

/// Coordinates the primary instance and any later launch of the same app.
///
/// Only the process holding the file lock starts the mouse module. Every other launch
/// asks the primary instance to show its settings window and exits, even when the
/// request is not answered: two sets of event taps must never run.
@MainActor
final class SingleInstanceCoordinator: NSObject {
    private static let showRequest = Notification.Name("com.moliduo.mac.showWindowRequest")
    private static let showResponse = Notification.Name("com.moliduo.mac.showWindowResponse")
    private static let identifierKey = "identifier"

    private let lock: SingleInstanceLock
    private var receivedResponses: Set<String> = []
    private var showHandler: (@MainActor () -> Void)?

    init(lock: SingleInstanceLock) {
        self.lock = lock
        super.init()
    }

    func acquireExclusiveInstance() throws -> Bool {
        try lock.acquire()
    }

    func releaseLock() {
        stopRespondingToShowRequests()
        lock.release()
    }

    /// Starts answering show requests. Call this once the window can be shown.
    func startRespondingToShowRequests(handler: @escaping @MainActor () -> Void) {
        guard lock.isHeld, showHandler == nil else {
            return
        }
        showHandler = handler
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowRequest(_:)),
            name: Self.showRequest,
            object: nil
        )
    }

    private func stopRespondingToShowRequests() {
        guard showHandler != nil else {
            return
        }
        showHandler = nil
        DistributedNotificationCenter.default().removeObserver(self, name: Self.showRequest, object: nil)
    }

    /// Asks the running instance to show its window, retrying while it starts up.
    /// - Returns: true when the running instance answered.
    @discardableResult
    func requestShowFromExistingInstance(timeout: TimeInterval = 2) -> Bool {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(handleShowResponse(_:)),
            name: Self.showResponse,
            object: nil
        )
        defer {
            center.removeObserver(self, name: Self.showResponse, object: nil)
        }

        let identifier = UUID().uuidString
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            center.post(name: Self.showRequest, object: nil, userInfo: [Self.identifierKey: identifier])
            RunLoop.current.run(mode: .default, before: min(Date().addingTimeInterval(0.1), deadline))
            if receivedResponses.contains(identifier) {
                return true
            }
        }
        return false
    }

    @objc private func handleShowRequest(_ notification: Notification) {
        guard let identifier = notification.userInfo?[Self.identifierKey] as? String else {
            return
        }
        showHandler?()
        DistributedNotificationCenter.default().post(
            name: Self.showResponse,
            object: nil,
            userInfo: [Self.identifierKey: identifier]
        )
    }

    @objc private func handleShowResponse(_ notification: Notification) {
        guard let identifier = notification.userInfo?[Self.identifierKey] as? String else {
            return
        }
        receivedResponses.insert(identifier)
    }
}
