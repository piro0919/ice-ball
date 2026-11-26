import AppKit

/// Everything needed to draw one display's overlay. Drawing happens only when this changes.
struct OverlayDrawModel: Equatable {
    /// The menu bar rectangle in view coordinates.
    var bar: CGRect
    var shapes: [CGRect]
    var configuration: AppearanceConfiguration
    var isDark: Bool
    var placement: OverlayPlacement
    /// The desktop picture under `bar`, needed only for `.aboveMenuBar`.
    var wallpaper: CGImage?
}

final class OverlayView: NSView {
    var model: OverlayDrawModel? {
        didSet {
            if model != oldValue { needsDisplay = true }
        }
    }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let model, !model.shapes.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let config = model.configuration
        let shape = ShapeLayout.path(for: model.shapes, cornerRadius: config.cornerRadius)

        // Outside of the shape: paint the desktop picture over the system menu bar
        // background so the bar appears to end at the shape's edge.
        if model.placement == .aboveMenuBar, let wallpaper = model.wallpaper {
            context.saveGState()
            context.addRect(model.bar)
            context.addPath(shape)
            context.clip(using: .evenOdd)
            context.draw(wallpaper, in: model.bar)
            context.restoreGState()
        }

        if config.shadowEnabled {
            context.saveGState()
            // Clip the shape out, so only the shadow (not the opaque caster) is visible
            // and a translucent fill does not darken.
            context.addRect(bounds)
            context.addPath(shape)
            context.clip(using: .evenOdd)
            context.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: config.shadowRadius * 2,
                color: CGColor(gray: 0, alpha: model.isDark ? 0.55 : 0.3)
            )
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.addPath(shape)
            context.fillPath()
            context.restoreGState()
        }

        let opacity = min(config.backgroundOpacity, model.placement.maximumFillOpacity)
        context.setFillColor(config.background(isDark: model.isDark).cgColor(multiplyingAlphaBy: opacity))
        context.addPath(shape)
        context.fillPath()

        if config.borderWidth > 0 {
            // Inside stroke: stroke at double width and clip to the shape.
            context.saveGState()
            context.addPath(shape)
            context.clip()
            context.setStrokeColor(config.borderColor.cgColor())
            context.setLineWidth(config.borderWidth * 2)
            context.addPath(shape)
            context.strokePath()
            context.restoreGState()
        }
    }
}
