import UIKit

/// Live Wire's tokens (app/assets/tailwind/base/tokens.css in the Rails app),
/// so native chrome matches the pages it frames. Each color resolves for the
/// current appearance, like the web's light-dark().
enum Palette {
    // Surfaces
    static let canvas = UIColor(light: 0xF3F5F9, dark: 0x06070B)
    static let canvasSunken = UIColor(light: 0xEAEEF4, dark: 0x0A0C12)
    static let surface = UIColor(light: 0xFFFFFF, dark: 0x0F121A)
    static let surfaceRaised = UIColor(light: 0xFFFFFF, dark: 0x141824)

    // Ink
    static let ink = UIColor(light: 0x0A0D14, dark: 0xE9ECF4)
    static let inkMuted = UIColor(light: 0x5A6374, dark: 0x8D96AA)
    static let inkFaint = UIColor(light: 0x7C8599, dark: 0x636B80)
    static let inkInverted = UIColor(light: 0xFFFFFF, dark: 0x06070B)

    // Hairlines
    static let line = UIColor(light: 0xD6DCE7, dark: 0x1C2130)
    static let lineStrong = UIColor(light: 0xC3CBDA, dark: 0x2A3144)
    static let dot = UIColor(light: 0x0A0D14, lightAlpha: 0.10, dark: 0xE9ECF4, darkAlpha: 0.08)

    // Meaning: a dot, an icon, an edge. Small text uses the -Ink variants.
    static let positive = UIColor(light: 0x13C977, dark: 0x44FF9A)
    static let positiveInk = UIColor(light: 0x0A8A50, dark: 0x44FF9A)
    static let live = UIColor(light: 0x1E8FE6, dark: 0x44B0FF)
    static let liveInk = UIColor(light: 0x1569B5, dark: 0x44B0FF)
    static let attention = UIColor(light: 0xD99A06, dark: 0xFFC247)
    static let attentionInk = UIColor(light: 0x8A5F00, dark: 0xFFC247)
    static let negative = UIColor(light: 0xF0552F, dark: 0xFF6644)
    static let negativeInk = UIColor(light: 0xC93A17, dark: 0xFF7F61)
}

// Nonisolated: UIKit and SwiftUI resolve dynamic colors on whatever thread
// is drawing, and a main-actor provider traps there.
extension UIColor {
    nonisolated convenience init(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) {
        self.init { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        }
    }

    nonisolated convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// `#RRGGBB` or `RRGGBB`, as bridge components send colors.
    nonisolated convenience init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(rgb: value)
    }
}
