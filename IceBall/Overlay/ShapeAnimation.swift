import CoreGraphics

/// Pure math for moving the shapes to their new frames, for example when the app menus
/// change width after an app switch. The overlay view runs the clock.
nonisolated enum ShapeAnimation {
    /// Seconds from the old frames to the new ones.
    static let duration: Double = 0.25

    /// Ease-out cubic: starts at full speed and slows to a stop, without overshooting.
    static func easeOut(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        let rest = 1 - t
        return 1 - rest * rest * rest
    }

    /// The frames at `progress` (0…1 of the duration), eased.
    static func interpolate(from: [CGRect], to: [CGRect], progress: Double) -> [CGRect] {
        guard from.count == to.count else { return to }
        let p = CGFloat(easeOut(progress))
        return zip(from, to).map { a, b in
            CGRect(
                x: a.minX + (b.minX - a.minX) * p,
                y: a.minY + (b.minY - a.minY) * p,
                width: a.width + (b.width - a.width) * p,
                height: a.height + (b.height - a.height) * p
            )
        }
    }

    /// The part of the view that changes between two steps, so each frame redraws only the
    /// moving end rather than the whole bar with its desktop picture and shadow.
    /// - Parameters:
    ///   - reach: How far a shape's drawing spreads past its edge (shadow, border); the
    ///     corner radius is added on the side where the shape ends.
    static func dirtyRect(
        from old: [CGRect], to new: [CGRect], in bounds: CGRect, cornerRadius: CGFloat, reach: CGFloat
    ) -> CGRect {
        guard old.count == new.count else { return bounds }
        var dirty = CGRect.null
        for (a, b) in zip(old, new) where a != b {
            let radius = max(0, min(cornerRadius, a.height / 2, b.height / 2))
            let minX: CGFloat
            let maxX: CGFloat
            if a.minX == b.minX {
                minX = min(a.maxX, b.maxX) - radius
                maxX = max(a.maxX, b.maxX)
            } else if a.maxX == b.maxX {
                minX = min(a.minX, b.minX)
                maxX = max(a.minX, b.minX) + radius
            } else {
                minX = min(a.minX, b.minX)
                maxX = max(a.maxX, b.maxX)
            }
            dirty = dirty.union(
                CGRect(x: minX - reach, y: bounds.minY, width: maxX - minX + reach * 2, height: bounds.height))
        }
        return dirty.isNull ? .zero : dirty.intersection(bounds)
    }

    /// Whether going from one draw model to the next should move the shapes rather than
    /// jump: only when the shapes alone changed and each one has a counterpart. A change of
    /// the bar (a resolution change), of the settings or of the placement jumps, so that
    /// moving a slider in the settings is followed at once.
    @MainActor static func shouldAnimate(from old: OverlayDrawModel, to new: OverlayDrawModel) -> Bool {
        old.bar == new.bar
            && old.configuration == new.configuration
            && old.placement == new.placement
            && !new.shapes.isEmpty
            && old.shapes.count == new.shapes.count
            && old.shapes != new.shapes
    }
}
