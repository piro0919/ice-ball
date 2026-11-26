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
    /// The fill taken from the desktop picture; nil uses the configured light or dark color.
    var desktopFill: RGBAColor? = nil
}

final class OverlayView: NSView {
    var model: OverlayDrawModel? {
        didSet {
            guard model != oldValue else { return }
            if let oldValue, let model, ShapeAnimation.shouldAnimate(from: oldValue, to: model),
                !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            {
                // A new target while moving starts from where the shapes are now.
                startAnimation(from: displayedShapes ?? oldValue.shapes, to: model.shapes)
            } else {
                stopShapeAnimation()
            }
            if model?.configuration.reachesTowardPointer != true {
                resetBulge()
            } else {
                updateBulgeTarget()
            }
            needsDisplay = true
        }
    }

    /// The frames being drawn while the shapes move; nil when they are at `model.shapes`.
    private(set) var displayedShapes: [CGRect]?
    private var animationFrom: [CGRect] = []
    private var animationStart: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private var lastStep: CFTimeInterval = 0

    // MARK: Reach toward pointer

    /// The pointer in view coordinates, or nil when it is away or a menu is open.
    private var pointer: CGPoint?
    private var bulgeSpring = Spring()
    private var bulgeTarget: Double = 0
    private var bulgeIndex = 0
    private var bulgeX: CGFloat = 0

    /// The swelling being drawn now, if any.
    private(set) var bulge: PointerReach.Bulge?

    /// Called by the controller as the pointer moves; nil when it should not pull the shape.
    func setPointer(_ point: CGPoint?) {
        guard point != pointer else { return }
        pointer = point
        updateBulgeTarget()
    }

    private func updateBulgeTarget() {
        guard let model, model.configuration.reachesTowardPointer,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return resetBulge() }
        let shapes = displayedShapes ?? model.shapes
        if let pointer,
            let target = PointerReach.target(
                pointer: pointer, shapes: shapes, cornerRadius: model.configuration.cornerRadius)
        {
            bulgeIndex = target.index
            bulgeX = target.x
            let depth = PointerReach.maximumDepth(
                shape: shapes[target.index], bar: model.bar, placement: model.placement)
            bulgeTarget = Double(depth * target.strength)
        } else {
            // Spring back where it is.
            bulgeTarget = 0
        }
        if !bulgeSpring.isSettled(at: bulgeTarget) || bulge.map({ $0.x != bulgeX || $0.index != bulgeIndex }) == true {
            startDisplayLink()
        }
    }

    private func resetBulge() {
        let hadBulge = bulge != nil
        bulgeSpring = Spring()
        bulgeTarget = 0
        bulge = nil
        if hadBulge { needsDisplay = true }
        stopDisplayLinkIfIdle()
    }

    private var isAnimatingShapes: Bool { displayedShapes != nil }

    private func startAnimation(from: [CGRect], to: [CGRect]) {
        animationFrom = from
        animationStart = CACurrentMediaTime()
        displayedShapes = from
        startDisplayLink()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(step))
        // 60 frames a second: each frame is a commit to the window server, and 120 on a
        // ProMotion display doubled the CPU time for little visible gain in 0.25 s.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastStep = CACurrentMediaTime()
    }

    private func stopShapeAnimation() {
        displayedShapes = nil
        stopDisplayLinkIfIdle()
    }

    private func stopDisplayLinkIfIdle() {
        guard !isAnimatingShapes, bulgeSpring.isSettled(at: bulgeTarget) else { return }
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let model else {
            displayedShapes = nil
            bulge = nil
            displayLink?.invalidate()
            displayLink = nil
            return
        }
        let now = CACurrentMediaTime()
        let dt = now - lastStep
        lastStep = now
        let config = model.configuration
        let reach = (config.shadowEnabled ? config.shadowRadius * 3 + 2 : 0) + config.borderWidth + 2

        if isAnimatingShapes {
            let before = displayedShapes ?? model.shapes
            let progress = (now - animationStart) / ShapeAnimation.duration
            if progress >= 1 {
                displayedShapes = nil
            } else {
                displayedShapes = ShapeAnimation.interpolate(from: animationFrom, to: model.shapes, progress: progress)
            }
            setNeedsDisplay(
                ShapeAnimation.dirtyRect(
                    from: before, to: displayedShapes ?? model.shapes, in: bounds,
                    cornerRadius: config.cornerRadius, reach: reach))
        }

        // The shapes move under a resting pointer after an app switch; follow them.
        updateBulgeTarget()
        let oldBulge = bulge
        bulgeSpring.step(toward: bulgeTarget, dt: dt)
        let shapes = displayedShapes ?? model.shapes
        // The spring overshoots its target; never past the deepest the placement allows.
        let deepest =
            shapes.indices.contains(bulgeIndex)
            ? PointerReach.maximumDepth(shape: shapes[bulgeIndex], bar: model.bar, placement: model.placement) : 0
        let depth = min(max(CGFloat(bulgeSpring.value), -PointerReach.maximumDip), deepest)
        bulge = abs(depth) > 0.05 ? PointerReach.Bulge(index: bulgeIndex, x: bulgeX, depth: depth) : nil
        if bulge != oldBulge {
            // Moving the swelling to the other shape of Split redraws both places.
            setNeedsDisplay(
                PointerReach.dirtyRect(from: oldBulge, to: bulge, shapes: shapes, in: bounds, reach: reach))
        }

        if !isAnimatingShapes && bulgeSpring.isSettled(at: bulgeTarget) {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let model, !model.shapes.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let config = model.configuration
        let shape = PointerReach.path(
            for: displayedShapes ?? model.shapes, cornerRadius: config.cornerRadius, bulge: bulge)

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
        context.setFillColor(
            (model.desktopFill ?? config.background(isDark: model.isDark)).cgColor(multiplyingAlphaBy: opacity))
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
