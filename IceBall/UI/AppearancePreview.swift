import SwiftUI

/// A miniature menu bar drawn with the same `ShapeLayout` as the real overlay.
struct AppearancePreview: View {
    let configuration: AppearanceConfiguration
    @Environment(\.colorScheme) private var colorScheme

    /// Widths of the drawn app menus and status items, measured after layout.
    /// Split's shapes are fitted to these, the way the overlay fits the real menu bar.
    /// Owned by the caller: `@State` needs the SwiftUI macro plugin, which `swiftc` from the
    /// Command Line Tools does not ship.
    let metrics: PreviewMetrics

    private let barHeight: CGFloat = 30
    private let contentInset: CGFloat = 16
    private let menuTitles = PreviewMetrics.menuTitles
    private let statusSymbols = PreviewMetrics.statusSymbols


    /// The two corners of the preview's diagonal gradient, which stands in for the desktop picture.
    static func backdrop(isDark: Bool) -> [RGBAColor] {
        isDark
            ? [RGBAColor(red: 0.13, green: 0.2, blue: 0.36), RGBAColor(red: 0.36, green: 0.18, blue: 0.4)]
            : [RGBAColor(red: 0.55, green: 0.75, blue: 0.95), RGBAColor(red: 0.95, green: 0.75, blue: 0.7)]
    }

    /// Roughly the average of the gradient along the top edge, where the bar sits.
    static func backdropAverage(isDark: Bool) -> RGBAColor {
        let c = backdrop(isDark: isDark)
        return RGBAColor(
            red: (c[0].red + c[1].red) / 2, green: (c[0].green + c[1].green) / 2, blue: (c[0].blue + c[1].blue) / 2)
    }

    var body: some View {
        GeometryReader { proxy in
            let isDark = colorScheme == .dark
            let bar = CGRect(x: 0, y: 8, width: proxy.size.width, height: barHeight)
            let shapes = ShapeLayout.rects(
                for: configuration, in: bar,
                leftExtent: metrics.menusWidth > 0 ? contentInset + metrics.menusWidth : nil,
                rightExtent: metrics.statusWidth > 0 ? metrics.statusWidth + contentInset : nil
            )

            let backdrop = Self.backdrop(isDark: isDark)

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: backdrop.map { Color(nsColor: $0.nsColor) },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                Canvas { context, _ in
                    guard !shapes.isEmpty else { return }
                    let path = Path(ShapeLayout.path(for: shapes, cornerRadius: configuration.cornerRadius))
                    if configuration.shadowEnabled {
                        var shadowed = context
                        shadowed.addFilter(
                            .shadow(
                                color: .black.opacity(isDark ? 0.55 : 0.3), radius: configuration.shadowRadius, y: 1))
                        shadowed.clip(
                            to: Path(CGRect(x: -50, y: -50, width: bar.width + 100, height: 200)).subtracting(path))
                        shadowed.fill(path, with: .color(.black))
                    }
                    // The preview's own backdrop stands in for the desktop picture.
                    let fill =
                        configuration.colorFromDesktopPicture
                        ? DesktopPictureColor.fill(from: Self.backdropAverage(isDark: isDark), isDark: isDark)
                        : configuration.background(isDark: isDark)
                    context.fill(
                        path, with: .color(Color(nsColor: fill.nsColor).opacity(configuration.backgroundOpacity)))
                    if configuration.borderWidth > 0 {
                        var clipped = context
                        clipped.clip(to: path)
                        clipped.stroke(
                            path, with: .color(Color(nsColor: configuration.borderColor.nsColor)),
                            lineWidth: configuration.borderWidth * 2)
                    }
                }

                // Text is kept on one line (SwiftUI would otherwise wrap it when space runs short).
                // The spacing fits everything inside the shape at the settings window's width (460 pt).
                HStack(spacing: 0) {
                    HStack(spacing: PreviewMetrics.menuSpacing) {
                        Image(systemName: "apple.logo")
                        ForEach(menuTitles, id: \.self) {
                            Text($0).fontWeight($0 == "Finder" ? .bold : .regular).fixedSize()
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.width
                    } action: {
                        metrics.menusWidth = $0
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: PreviewMetrics.statusSpacing) {
                        ForEach(statusSymbols, id: \.self) { Image(systemName: $0) }
                        Text(PreviewMetrics.clock).fixedSize()
                    }
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.width
                    } action: {
                        metrics.statusWidth = $0
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(isDark ? .white : .black)
                .padding(.horizontal, contentInset)
                .frame(height: barHeight)
                .offset(y: bar.minY)
            }
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.previewLabel)
    }
}

@Observable
final class PreviewMetrics {
    static let menuTitles = L.previewMenus
    static let statusSymbols = ["wifi", "battery.75percent", "magnifyingglass", "switch.2"]
    static let clock = "11:27"
    static let menuSpacing: CGFloat = 12
    static let statusSpacing: CGFloat = 10
    static let fontSize: CGFloat = 12

    /// Start from widths computed with AppKit so that Split shows two shapes in the very
    /// first frame; the measured widths replace them after layout.
    var menusWidth: CGFloat = PreviewMetrics.estimatedMenusWidth
    var statusWidth: CGFloat = PreviewMetrics.estimatedStatusWidth

    private static func textWidth(_ text: String, bold: Bool = false) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func symbolWidth(_ name: String) -> CGFloat {
        let config = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
        guard
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        else { return fontSize }
        return image.alignmentRect.width
    }

    static var estimatedMenusWidth: CGFloat {
        let titles = menuTitles.reduce(0) { $0 + textWidth($1, bold: $1 == "Finder") }
        return symbolWidth("apple.logo") + titles + menuSpacing * CGFloat(menuTitles.count)
    }

    static var estimatedStatusWidth: CGFloat {
        let symbols = statusSymbols.reduce(0) { $0 + symbolWidth($1) }
        return symbols + textWidth(clock) + statusSpacing * CGFloat(statusSymbols.count)
    }
}
