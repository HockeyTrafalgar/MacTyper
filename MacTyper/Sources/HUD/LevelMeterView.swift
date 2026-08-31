import AppKit

/// EQ-style mic-activity meter: five rounded vertical bars whose heights
/// track a 0..1 level, center-weighted so the cluster reads as an organic
/// "listening" visual. Opacity rises with level.
final class LevelMeterView: NSView {
    private static let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.8, 0.5]
    private static let barW: CGFloat = 3.0
    private static let gap: CGFloat = 3.5
    private static let minH: CGFloat = 4.0

    private var level: CGFloat = 0

    func setLevel(_ newLevel: Double) {
        let lvl = CGFloat(max(0, min(1, newLevel)))
        // Skip redraws for imperceptible changes, but always honor a
        // return-to-zero so the meter settles.
        if abs(lvl - level) < 0.01 && !(lvl == 0 && level != 0) { return }
        level = lvl
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let n = Self.weights.count
        let totalW = CGFloat(n) * Self.barW + CGFloat(n - 1) * Self.gap
        let x0 = (bounds.width - totalW) / 2
        let cy = bounds.height / 2
        let maxH = bounds.height
        for (i, weight) in Self.weights.enumerated() {
            let lvl = level * weight
            let h = Self.minH + lvl * (maxH - Self.minH)
            let x = x0 + CGFloat(i) * (Self.barW + Self.gap)
            let rect = NSRect(x: x, y: cy - h / 2, width: Self.barW, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: Self.barW / 2, yRadius: Self.barW / 2)
            OverlayTheme.ink(alpha: 0.22 + 0.63 * min(1, lvl)).setFill()
            path.fill()
        }
    }
}

/// Theme helpers shared by the HUD views.
enum OverlayTheme {
    static var isDark: Bool {
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            return style.lowercased().contains("dark")
        }
        return NSApp.effectiveAppearance.name.rawValue.contains("Dark")
    }

    /// Near-black on a light surface, near-white on a dark one.
    static func ink(alpha: CGFloat = 0.55) -> NSColor {
        NSColor(calibratedWhite: isDark ? 1.0 : 0.0, alpha: alpha)
    }
}
