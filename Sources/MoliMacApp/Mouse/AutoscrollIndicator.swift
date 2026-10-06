import AppKit
import SwiftUI

/// The mark at the point where autoscroll started, as on Windows.
@MainActor
final class AutoscrollIndicator {
    private static let size: CGFloat = 32
    private var panel: NSPanel?

    /// `point` is in screen coordinates with the origin at the top left (CGEvent's).
    func show(at point: CGPoint?) {
        guard let point else {
            panel?.orderOut(nil)
            return
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        // AppKit counts from the bottom of the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        panel.setFrameOrigin(NSPoint(
            x: point.x - Self.size / 2,
            y: primaryHeight - point.y - Self.size / 2
        ))
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: Mark())
        return panel
    }

    private struct Mark: View {
        var body: some View {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: AutoscrollIndicator.size, height: AutoscrollIndicator.size)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator))
        }
    }
}
