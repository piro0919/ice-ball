import CoreGraphics

/// Pure geometry: which rounded rectangles to draw for a configuration.
/// Shared by the overlay and the settings preview so both always agree.
nonisolated enum ShapeLayout {
    /// Space kept between the content of a split region and the edge of its shape.
    static let splitPadding: CGFloat = 8
    /// Split falls back to one shape when its two halves would be closer than this.
    static let minimumSplitGap: CGFloat = 12

    /// - Parameters:
    ///   - bar: The menu bar rectangle, in the drawing coordinate space.
    ///   - leftExtent: Width from `bar.minX` to the end of the application menus.
    ///   - rightExtent: Width from the start of the status items to `bar.maxX`.
    static func rects(
        for configuration: AppearanceConfiguration,
        in bar: CGRect,
        leftExtent: CGFloat?,
        rightExtent: CGFloat?
    ) -> [CGRect] {
        let inner = bar.insetBy(dx: configuration.horizontalMargin, dy: configuration.verticalMargin)
        guard inner.width > 0, inner.height > 0 else { return [] }

        switch configuration.shape {
        case .standard:
            return []
        case .rounded:
            return [inner]
        case .split:
            guard let leftExtent, let rightExtent, leftExtent > 0, rightExtent > 0 else {
                // Without measurements, Split looks like Rounded instead of guessing widths.
                return [inner]
            }
            let leftMaxX = min(bar.minX + leftExtent + splitPadding, inner.maxX)
            let rightMinX = max(bar.maxX - rightExtent - splitPadding, inner.minX)
            let left = CGRect(x: inner.minX, y: inner.minY, width: leftMaxX - inner.minX, height: inner.height)
            let right = CGRect(x: rightMinX, y: inner.minY, width: inner.maxX - rightMinX, height: inner.height)
            guard left.width > 0, right.width > 0, left.maxX + minimumSplitGap <= right.minX else {
                return [inner]
            }
            return [left, right]
        }
    }

    static func path(for rects: [CGRect], cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for rect in rects {
            let radius = max(0, min(cornerRadius, rect.height / 2, rect.width / 2))
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }
}
