import CoreGraphics
import MoliMacCore
import QuartzCore

/// Turns mouse movement while a button is held into the drag actions. Runs on the
/// event tap thread.
///
/// For desktop switching and scrolling the pointer is detached from the mouse, so it
/// stays where the drag began; `end` always reattaches it.
final class DragEngine {
    private enum State {
        case idle
        case spaces(SpacesDrag)
        case scroll(DragScroll)
        case middleButton
    }

    private let scroll: ScrollEngine
    private var state = State.idle

    init(scroll: ScrollEngine) {
        self.scroll = scroll
    }

    func begin(_ action: MouseAction) {
        end()
        switch action {
        case .dragSpacesAndMissionControl:
            state = .spaces(SpacesDrag())
            freezePointer(true)
        case .dragScrollAndNavigate:
            state = .scroll(DragScroll())
            freezePointer(true)
            scroll.beginDragScroll()
        case .dragMiddleButton:
            state = .middleButton
            SyntheticEvents.postMouse(button: 3, down: true)
        default:
            Log.mouse.error("not a drag action: \(String(describing: action), privacy: .public)")
        }
    }

    /// - Returns: true when the movement event must not reach apps.
    func move(_ event: CGEvent, dx: Double, dy: Double) -> Bool {
        switch state {
        case .idle:
            return false
        case var .spaces(drag):
            let actions = drag.move(dx: dx, dy: dy)
            state = .spaces(drag)
            actions.forEach(ActionPerformer.perform)
            return true
        case var .scroll(drag):
            let delta = drag.move(dx: dx, dy: dy, time: CACurrentMediaTime())
            state = .scroll(drag)
            if delta.dx != 0 || delta.dy != 0 {
                scroll.dragScroll(dx: delta.dx, dy: delta.dy)
            }
            return true
        case .middleButton:
            // Apps see the drag as coming from the middle button they saw go down.
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(CGMouseButton.center.rawValue))
            return false
        }
    }

    func end() {
        switch state {
        case .idle:
            return
        case .spaces:
            freezePointer(false)
        case let .scroll(drag):
            freezePointer(false)
            let now = CACurrentMediaTime()
            scroll.endDragScroll(
                velocity: drag.releaseVelocity(at: now),
                horizontal: drag.axis == .horizontal,
                now: now
            )
        case .middleButton:
            SyntheticEvents.postMouse(button: 3, down: false)
        }
        state = .idle
    }

    private func freezePointer(_ frozen: Bool) {
        CGAssociateMouseAndMouseCursorPosition(frozen ? 0 : 1)
    }
}
