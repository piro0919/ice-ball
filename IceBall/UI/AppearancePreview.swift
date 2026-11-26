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
    private let menuTitles = ["Finder", "ファイル", "編集", "表示"]
    private let statusSymbols = ["wifi", "battery.75percent", "magnifyingglass", "switch.2"]

    var body: some View {
        GeometryReader { proxy in
            let isDark = colorScheme == .dark
            let bar = CGRect(x: 0, y: 8, width: proxy.size.width, height: barHeight)
            let shapes = ShapeLayout.rects(
                for: configuration, in: bar,
                leftExtent: metrics.menusWidth > 0 ? contentInset + metrics.menusWidth : nil,
                rightExtent: metrics.statusWidth > 0 ? metrics.statusWidth + contentInset : nil
            )

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: isDark ? [Color(red: 0.13, green: 0.2, blue: 0.36), Color(red: 0.36, green: 0.18, blue: 0.4)]
                        : [Color(red: 0.55, green: 0.75, blue: 0.95), Color(red: 0.95, green: 0.75, blue: 0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                Canvas { context, _ in
                    guard !shapes.isEmpty else { return }
                    let path = Path(ShapeLayout.path(for: shapes, cornerRadius: configuration.cornerRadius))
                    if configuration.shadowEnabled {
                        var shadowed = context
                        shadowed.addFilter(.shadow(color: .black.opacity(isDark ? 0.55 : 0.3), radius: configuration.shadowRadius, y: 1))
                        shadowed.clip(to: Path(CGRect(x: -50, y: -50, width: bar.width + 100, height: 200)).subtracting(path))
                        shadowed.fill(path, with: .color(.black))
                    }
                    let fill = configuration.background(isDark: isDark)
                    context.fill(path, with: .color(Color(nsColor: fill.nsColor).opacity(configuration.backgroundOpacity)))
                    if configuration.borderWidth > 0 {
                        var clipped = context
                        clipped.clip(to: path)
                        clipped.stroke(path, with: .color(Color(nsColor: configuration.borderColor.nsColor)), lineWidth: configuration.borderWidth * 2)
                    }
                }

                // Text is kept on one line (SwiftUI would otherwise wrap it when space runs short).
                // The spacing fits everything inside the shape at the settings window's width (460 pt).
                HStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                        ForEach(menuTitles, id: \.self) {
                            Text($0).fontWeight($0 == "Finder" ? .bold : .regular).fixedSize()
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { metrics.menusWidth = $0 }
                    Spacer(minLength: 12)
                    HStack(spacing: 10) {
                        ForEach(statusSymbols, id: \.self) { Image(systemName: $0) }
                        Text("11:27").fixedSize()
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { metrics.statusWidth = $0 }
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
        .accessibilityLabel("外観のプレビュー")
    }
}

@Observable
final class PreviewMetrics {
    var menusWidth: CGFloat = 0
    var statusWidth: CGFloat = 0
}
