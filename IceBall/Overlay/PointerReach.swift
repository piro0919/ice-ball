import CoreGraphics
import Foundation

/// Pure math for "Reach Toward Pointer": the bottom edge of the shape nearest the pointer
/// swells toward it like a drop of water, and springs back when the pointer leaves.
/// The overlay view runs the clock; the controller feeds the pointer position.
nonisolated enum PointerReach {
    /// The swelling starts when the pointer is this close to a shape's bottom edge.
    static let range: CGFloat = 40
    /// How far the edge swells at most, with the pointer at or above the edge.
    static let maximumDepth: CGFloat = 6
    /// Half the width of the swelling along the edge.
    static let halfWidth: CGFloat = 26
    /// While springing back the edge may dip into the shape; never further than this.
    static let maximumDip: CGFloat = 1.5

    /// How deep the swelling may go for `shape`. Above the menu bar ("Show menu bar
    /// background" on), the shape is seen over the system's own bar; past the bar's bottom
    /// edge that bar is missing and the swelling showed as a lighter strip, so it stays
    /// inside the bar there.
    @MainActor static func maximumDepth(shape: CGRect, bar: CGRect, placement: OverlayPlacement) -> CGFloat {
        switch placement {
        case .belowMenuBar: maximumDepth
        case .aboveMenuBar: min(maximumDepth, max(0, shape.minY - bar.minY))
        }
    }

    /// A swelling on the bottom edge of `shapes[index]`, centered at `x`, `depth` points deep.
    struct Bulge: Equatable {
        var index: Int
        var x: CGFloat
        var depth: CGFloat
    }

    /// Where to swell and how strongly (0…1) for a pointer at `pointer`; nil when no shape is
    /// within range. All in the view's coordinates, y growing upward.
    static func target(pointer: CGPoint, shapes: [CGRect], cornerRadius: CGFloat)
        -> (index: Int, x: CGFloat, strength: CGFloat)?
    {
        var best: (index: Int, distance: CGFloat)?
        for (index, shape) in shapes.enumerated() {
            let dx = max(shape.minX - pointer.x, 0, pointer.x - shape.maxX)
            let dy = max(shape.minY - pointer.y, 0)
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < range, distance < best?.distance ?? .infinity {
                best = (index, distance)
            }
        }
        guard let best else { return nil }
        let shape = shapes[best.index]
        let radius = max(0, min(cornerRadius, shape.height / 2, shape.width / 2))
        // The swelling stays on the straight part of the edge, clear of the corners.
        let lowest = shape.minX + radius + halfWidth
        let highest = shape.maxX - radius - halfWidth
        guard lowest <= highest else { return nil }
        let t = 1 - best.distance / range
        let strength = t * t * (3 - 2 * t)  // smoothstep: no sudden start at the edge of the range
        return (best.index, min(max(pointer.x, lowest), highest), strength)
    }

    /// The shapes' outline with `bulge` applied, as one closed subpath per shape, so even-odd
    /// clipping (shadow, desktop picture) keeps working.
    static func path(for rects: [CGRect], cornerRadius: CGFloat, bulge: Bulge?) -> CGPath {
        guard let bulge, rects.indices.contains(bulge.index), abs(bulge.depth) > 0.05 else {
            return ShapeLayout.path(for: rects, cornerRadius: cornerRadius)
        }
        let path = CGMutablePath()
        for (index, rect) in rects.enumerated() {
            let radius = max(0, min(cornerRadius, rect.height / 2, rect.width / 2))
            guard index == bulge.index else {
                path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
                continue
            }
            // Kept on the straight part of the edge even if the shape changed under it.
            let lowest = rect.minX + radius + halfWidth
            let highest = rect.maxX - radius - halfWidth
            guard lowest <= highest else {
                path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
                continue
            }
            let x = min(max(bulge.x, lowest), highest)
            let w = halfWidth
            let bottom = rect.minY - bulge.depth
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
                radius: radius)
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY),
                radius: radius)
            // Right to left along the bottom edge, through the swelling. Flat tangents at both
            // ends and at the lowest point keep it smooth.
            path.addLine(to: CGPoint(x: x + w, y: rect.minY))
            path.addCurve(
                to: CGPoint(x: x, y: bottom),
                control1: CGPoint(x: x + w * 0.5, y: rect.minY), control2: CGPoint(x: x + w * 0.45, y: bottom))
            path.addCurve(
                to: CGPoint(x: x - w, y: rect.minY),
                control1: CGPoint(x: x - w * 0.45, y: bottom), control2: CGPoint(x: x - w * 0.5, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
                radius: radius)
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
                radius: radius)
            path.closeSubpath()
        }
        return path
    }

    /// The part of the view that changes when the swelling goes from `old` to `new`.
    static func dirtyRect(from old: Bulge?, to new: Bulge?, shapes: [CGRect], in bounds: CGRect, reach: CGFloat)
        -> CGRect
    {
        var dirty = CGRect.null
        for bulge in [old, new].compactMap({ $0 }) where shapes.indices.contains(bulge.index) {
            let shape = shapes[bulge.index]
            dirty = dirty.union(
                CGRect(
                    x: bulge.x - halfWidth - reach, y: bounds.minY,
                    width: (halfWidth + reach) * 2, height: shape.minY + reach + maximumDepth - bounds.minY))
        }
        return dirty.isNull ? .zero : dirty.intersection(bounds)
    }
}

/// A damped spring for one value, stepped once a frame. Underdamped, so it overshoots a little
/// and settles: the "springy" return of the swelling.
nonisolated struct Spring: Equatable {
    /// Seconds for one oscillation without damping; smaller is snappier.
    static let response: Double = 0.32
    /// Below 1 overshoots; 1 would settle without overshooting.
    static let dampingRatio: Double = 0.55

    var value: Double = 0
    var velocity: Double = 0

    var isSettled: Bool { abs(velocity) < 0.05 && abs(value) < 0.01 }

    func isSettled(at target: Double) -> Bool {
        abs(velocity) < 0.05 && abs(value - target) < 0.01
    }

    /// Advances by `dt` seconds toward `target`, in small sub-steps so a long frame stays stable.
    mutating func step(toward target: Double, dt: Double) {
        let stiffness = pow(2 * Double.pi / Self.response, 2)
        let damping = 4 * Double.pi * Self.dampingRatio / Self.response
        var remaining = min(dt, 0.1)
        while remaining > 0 {
            let h = min(remaining, 1.0 / 240)
            let acceleration = -stiffness * (value - target) - damping * velocity
            velocity += acceleration * h
            value += velocity * h
            remaining -= h
        }
        if isSettled(at: target) {
            value = target
            velocity = 0
        }
    }
}
