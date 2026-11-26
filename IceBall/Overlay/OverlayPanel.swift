import AppKit

/// Where the overlay sits relative to the system menu bar window.
enum OverlayPlacement: Equatable {
    /// Below the menu bar window. Used while the menu bar is transparent (the macOS 26+
    /// default): the system keeps drawing menus and status items on top of our shape.
    case belowMenuBar
    /// Above the menu bar window, as Ice does. Needed when "Show menu bar background" is
    /// on, because the system background would otherwise hide the shape. The area outside
    /// the shape is painted with the desktop picture, and the fill covers the menu text,
    /// so its opacity is capped.
    case aboveMenuBar

    var windowLevel: NSWindow.Level {
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return switch self {
        case .belowMenuBar: NSWindow.Level(rawValue: menuBarLevel - 1)
        case .aboveMenuBar: NSWindow.Level(rawValue: menuBarLevel + 1)
        }
    }

    /// Highest fill opacity allowed, so menu titles stay readable when drawn over.
    var maximumFillOpacity: Double {
        switch self {
        case .belowMenuBar: 1
        case .aboveMenuBar: 0.35
        }
    }
}

/// A borderless, click-through panel covering one display's menu bar.
final class OverlayPanel: NSPanel {
    /// Extra room under the menu bar for the drop shadow.
    static let shadowMargin: CGFloat = 16

    let displayID: CGDirectDisplayID
    let overlayView = OverlayView()

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        // No .fullScreenAuxiliary: the panel stays out of full-screen spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenDisallowsTiling]
        contentView = overlayView
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // A borderless window may sit over the menu bar; never let AppKit push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
