import AppKit
import SwiftUI

/// Colours from the design tokens (MoliSpec 011, Config/tokens.json). MoliMac is
/// one of the neutral apps: its accent is graphite rather than a hue.
enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(hex: 0xD4D4D8) : NSColor(hex: 0x3F3F46)
    })
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum MenuBarIcon {
    /// The template icon packaged as a resource, or an SF Symbol when running
    /// outside an app bundle (`swift run`).
    static func image() -> NSImage {
        let image = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "command", accessibilityDescription: nil)
            ?? NSImage()
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }
}
