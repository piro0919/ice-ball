import AppKit

/// Read-only facts about the system menu bar, gathered with public APIs only.
///
/// Coordinates named `cg…` use the Core Graphics global space (origin at the top-left
/// of the primary display, y grows downward). Cocoa rects use the AppKit space
/// (origin at the bottom-left of the primary display, y grows upward). x is the
/// same in both spaces.
nonisolated enum SystemMenuBar {
    /// Frames of the WindowServer-owned "Menubar" windows, one per display that has a menu bar.
    ///
    /// `CGWindowListCopyWindowInfo` is public and, on macOS 26/27, returns the name of
    /// WindowServer windows without the Screen Recording permission.
    static func cgMenuBarFrames(from windows: [[String: Any]]) -> [CGRect] {
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return windows.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == menuLevel,
                info[kCGWindowOwnerName as String] as? String == "Window Server",
                info[kCGWindowName as String] as? String == "Menubar",
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                bounds.width > 0, bounds.height > 0
            else { return nil }
            return bounds
        }
    }

    /// On-screen windows including desktop-level ones (needed for the full-screen check).
    static func onScreenWindows() -> [[String: Any]] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    /// Displays currently showing a full-screen space.
    ///
    /// Ice asks the private `CGSSpaceGetType`. Here the public window list is used: on
    /// macOS 27.2.1 a full-screen space puts a WindowManager window named
    /// "Fullscreen Backdrop" over its display, and removes it on leaving. The window name
    /// is undocumented. Geometry alone does not work: on a notched display the full-screen
    /// window sits below the notch, exactly where a zoomed window would.
    static func fullScreenDisplayIDs(from windows: [[String: Any]]) -> Set<CGDirectDisplayID> {
        let displays = NSScreen.screens.map { ($0.displayID, CGDisplayBounds($0.displayID)) }
        var result = Set<CGDirectDisplayID>()
        for info in windows {
            guard info[kCGWindowOwnerName as String] as? String == "WindowManager",
                info[kCGWindowName as String] as? String == "Fullscreen Backdrop",
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            for (id, displayBounds) in displays where displayBounds.intersects(bounds) {
                result.insert(id)
            }
        }
        return result
    }

    /// Whether "Show menu bar background" appears to be on.
    ///
    /// Read from the global defaults domain. The key name was found on a macOS 27.2.1
    /// machine; its mapping to the System Settings switch has not been verified by
    /// toggling it, so treat a wrong value as a known risk (see README).
    static var showsBackground: Bool {
        // Read through UserDefaults.standard (which includes the global domain) so the value
        // matches what key-value observing just reported; persistentDomain(forName:) lagged.
        UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
    }

    /// Whether "Automatically hide and show the menu bar" is set to always hide.
    static var autoHides: Bool {
        UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
    }

    /// Global defaults whose changes require a new layout.
    static let observedDefaultsKeys = ["_HIHideMenuBar", "SLSMenuBarUseBlurredAppearance"]

    static func cocoaRect(fromCG rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

nonisolated extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// The horizontal span hidden by the camera housing, in global x coordinates.
    var notchXRange: ClosedRange<CGFloat>? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea, right.minX > left.maxX else {
            return nil
        }
        return (frame.minX + left.maxX)...(frame.minX + right.minX)
    }
}
