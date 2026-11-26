import AppKit

/// The overall shape the overlay gives the menu bar.
nonisolated enum MenuBarShape: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The standard macOS menu bar. No overlay is shown.
    case standard
    /// One rounded shape spanning the whole menu bar.
    case rounded
    /// Two rounded shapes: one around the application menus, one around the status items.
    case split

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Default"
        case .rounded: "Rounded"
        case .split: "Split"
        }
    }
}

/// An sRGB color that can be persisted.
nonisolated struct RGBAColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    func cgColor(multiplyingAlphaBy factor: Double = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha * factor)
    }
}

/// Every user-adjustable appearance parameter.
nonisolated struct AppearanceConfiguration: Codable, Equatable, Sendable {
    var shape: MenuBarShape = .rounded
    var cornerRadius: Double = 10
    var horizontalMargin: Double = 6
    var verticalMargin: Double = 3
    /// Fill used while the menu bar is drawn with a light appearance.
    var lightBackground = RGBAColor(red: 1, green: 1, blue: 1)
    /// Fill used while the menu bar is drawn with a dark appearance.
    var darkBackground = RGBAColor(red: 0.11, green: 0.11, blue: 0.12)
    var backgroundOpacity: Double = 0.55
    /// Take the fill's hue from the desktop picture under the menu bar instead of the two
    /// colors above, which remain the fallback when the picture cannot be read.
    var colorFromDesktopPicture = false
    var borderColor = RGBAColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.6)
    var borderWidth: Double = 0
    var shadowEnabled = true
    var shadowRadius: Double = 4

    static let `default` = AppearanceConfiguration()

    static let cornerRadiusRange: ClosedRange<Double> = 0...20
    static let horizontalMarginRange: ClosedRange<Double> = 0...40
    static let verticalMarginRange: ClosedRange<Double> = 0...8
    static let borderWidthRange: ClosedRange<Double> = 0...4
    static let shadowRadiusRange: ClosedRange<Double> = 1...10

    init() {}

    // Missing keys fall back to defaults so that adding a parameter later
    // does not throw away the rest of a saved configuration.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppearanceConfiguration.default
        shape = (try? c.decode(MenuBarShape.self, forKey: .shape)) ?? d.shape
        cornerRadius = (try? c.decode(Double.self, forKey: .cornerRadius)) ?? d.cornerRadius
        horizontalMargin = (try? c.decode(Double.self, forKey: .horizontalMargin)) ?? d.horizontalMargin
        verticalMargin = (try? c.decode(Double.self, forKey: .verticalMargin)) ?? d.verticalMargin
        lightBackground = (try? c.decode(RGBAColor.self, forKey: .lightBackground)) ?? d.lightBackground
        darkBackground = (try? c.decode(RGBAColor.self, forKey: .darkBackground)) ?? d.darkBackground
        backgroundOpacity = (try? c.decode(Double.self, forKey: .backgroundOpacity)) ?? d.backgroundOpacity
        colorFromDesktopPicture =
            (try? c.decode(Bool.self, forKey: .colorFromDesktopPicture)) ?? d.colorFromDesktopPicture
        borderColor = (try? c.decode(RGBAColor.self, forKey: .borderColor)) ?? d.borderColor
        borderWidth = (try? c.decode(Double.self, forKey: .borderWidth)) ?? d.borderWidth
        shadowEnabled = (try? c.decode(Bool.self, forKey: .shadowEnabled)) ?? d.shadowEnabled
        shadowRadius = (try? c.decode(Double.self, forKey: .shadowRadius)) ?? d.shadowRadius
    }

    func background(isDark: Bool) -> RGBAColor {
        isDark ? darkBackground : lightBackground
    }
}
