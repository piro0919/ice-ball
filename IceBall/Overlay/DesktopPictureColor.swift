import Foundation

/// Pure color math for "Color from desktop picture": the hue of the desktop picture under the
/// menu bar, at a lightness that keeps the menu titles readable.
nonisolated enum DesktopPictureColor {
    /// Lightness of the fill behind light (white) menu titles.
    static let darkLightness = 0.22
    /// Lightness of the fill behind dark (black) menu titles.
    static let lightLightness = 0.86
    /// Strong colors are toned down so the fill stays a background, not a highlight.
    static let maximumSaturation = 0.5

    /// - Parameters:
    ///   - average: The average color of the desktop picture under the bar.
    ///   - isDark: Whether macOS draws the menu titles light (over a dark picture).
    static func fill(from average: RGBAColor, isDark: Bool) -> RGBAColor {
        let (hue, saturation, _) = hsl(average)
        return color(
            hue: hue, saturation: min(saturation, maximumSaturation),
            lightness: isDark ? darkLightness : lightLightness)
    }

    /// Hue (0–1), saturation and lightness of an sRGB color.
    static func hsl(_ c: RGBAColor) -> (hue: Double, saturation: Double, lightness: Double) {
        let maxC = max(c.red, c.green, c.blue)
        let minC = min(c.red, c.green, c.blue)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0.0001 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxC {
        case c.red: hue = ((c.green - c.blue) / delta).truncatingRemainder(dividingBy: 6)
        case c.green: hue = (c.blue - c.red) / delta + 2
        default: hue = (c.red - c.green) / delta + 4
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, min(saturation, 1), lightness)
    }

    static func color(hue: Double, saturation: Double, lightness: Double) -> RGBAColor {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let h = hue * 6
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) =
            switch h {
            case ..<1: (chroma, x, 0)
            case ..<2: (x, chroma, 0)
            case ..<3: (0, chroma, x)
            case ..<4: (0, x, chroma)
            case ..<5: (x, 0, chroma)
            default: (chroma, 0, x)
            }
        let m = lightness - chroma / 2
        return RGBAColor(red: r + m, green: g + m, blue: b + m)
    }
}
