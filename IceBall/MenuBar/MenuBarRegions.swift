import CoreGraphics

/// How much of each menu bar the application menus and the status items occupy,
/// measured from the display edges.
///
/// App menus differ per display: on macOS 27.2.1, each display's menu bar shows the app of
/// its frontmost window, and an Accessibility hit test on that menu bar returns that app's
/// menu bar with frames on that display. (Ice's `getApplicationMenuFrame` notes the opposite
/// for older systems.) Status items are only reported for the active display; they are laid
/// out from the right edge identically on every display, so one extent serves all.
nonisolated struct MenuBarRegions: Equatable, Sendable {
    /// Per display: distance from its left edge to the right end of its last app menu.
    var applicationMenuExtents: [CGDirectDisplayID: CGFloat] = [:]
    /// Distance from the left end of the leftmost status item to the right edge of the display.
    var statusItemsExtent: CGFloat?

    /// Frames are in CG global coordinates. Only frames inside the display's menu bar strip count.
    static func applicationMenuExtent(frames: [CGRect], on display: DisplayInfo) -> CGFloat? {
        let onDisplay = frames.filter { display.contains($0) }
        guard let maxX = onDisplay.map(\.maxX).max() else { return nil }
        let extent = maxX - display.bounds.minX
        return extent > 0 ? extent : nil
    }

    static func statusItemsExtent(frames: [CGRect], displays: [DisplayInfo]) -> CGFloat? {
        guard let display = bestDisplay(for: frames, in: displays) else { return nil }
        let onDisplay = frames.filter { frame in
            guard display.contains(frame) else { return false }
            // Items that macOS parks behind the camera housing are not visible.
            if let notch = display.notchXRange, frame.minX >= notch.lowerBound, frame.maxX <= notch.upperBound {
                return false
            }
            return true
        }
        // Visible status items sit side by side from the right edge. Accessibility also
        // reports items that are not drawn, at positions apart from that run (seen on
        // macOS 27.2.1: one 114 pt left of the rest), so keep only the contiguous run.
        var leftEdge: CGFloat?
        for frame in onDisplay.sorted(by: { $0.maxX > $1.maxX }) {
            if let edge = leftEdge, frame.maxX < edge - maximumStatusItemGap { break }
            leftEdge = min(leftEdge ?? frame.minX, frame.minX)
        }
        guard let minX = leftEdge else { return nil }
        let extent = display.bounds.maxX - minX
        return extent > 0 ? extent : nil
    }

    /// Largest horizontal gap still treated as part of the same run of status items.
    static let maximumStatusItemGap: CGFloat = 16

    private static func bestDisplay(for frames: [CGRect], in displays: [DisplayInfo]) -> DisplayInfo? {
        displays
            .map { display in (display, frames.filter { display.contains($0) }.count) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    nonisolated struct DisplayInfo: Sendable {
        var displayID: CGDirectDisplayID = 0
        var bounds: CGRect
        var menuBarHeight: CGFloat
        var hasMenuBar = true
        var notchXRange: ClosedRange<CGFloat>?

        /// Whether `frame` overlaps this display's menu bar strip.
        ///
        /// Accessibility can report menu frames shifted vertically by the difference between
        /// the displays' menu bar heights (seen as y = +9 and y = -9 with 30 pt and 39 pt
        /// bars), so only vertical overlap is required, not containment.
        func contains(_ frame: CGRect) -> Bool {
            frame.midX >= bounds.minX && frame.midX < bounds.maxX
                && frame.maxY > bounds.minY && frame.minY < bounds.minY + menuBarHeight
        }
    }
}
