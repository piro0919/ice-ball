import AppKit
import ApplicationServices

/// Reads the frames of the application menus and of the status items through the
/// public Accessibility API. All work runs on a private serial queue so the main
/// thread never waits for another process.
///
/// Why Accessibility and not the window list: on macOS 27.2.1 neither the public
/// `CGWindowListCopyWindowInfo` nor the private `CGSGetProcessMenuBarWindowList`
/// (which Ice uses) returns windows for status items any more; the latter only
/// returns the "Menubar" windows. Each app's `AXExtrasMenuBar` still lists its items.
nonisolated final class MenuBarRegionReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "IceBall.MenuBarRegionReader", qos: .utility)

    /// Processes that owned at least one status item at the last scan. Queue-confined.
    private var statusItemOwners = Set<pid_t>()

    /// Per-call timeout for Accessibility messages, so one hung app cannot stall a scan.
    private static let messagingTimeout: Float = 0.1

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Frames, in CG global coordinates, of the top-level menus shown in the menu bar of the
    /// display with CG bounds `displayBounds`.
    func applicationMenuFrames(atMenuBarOf displayBounds: CGRect) async -> [CGRect] {
        await withCheckedContinuation { continuation in
            queue.async {
                // Hit-test the menu bar's left end to learn which app it is showing.
                let systemWide = AXUIElementCreateSystemWide()
                AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
                var hit: AXUIElement?
                var pid: pid_t = 0
                guard AXUIElementCopyElementAtPosition(systemWide, Float(displayBounds.minX + 5), Float(displayBounds.minY + 5), &hit) == .success,
                      let hit, AXUIElementGetPid(hit, &pid) == .success
                else {
                    continuation.resume(returning: [])
                    return
                }
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
                guard let menuBar: AXUIElement = Self.attribute(app, kAXMenuBarAttribute) else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: Self.childFrames(of: menuBar))
            }
        }
    }

    /// Frames, in CG global coordinates, of all status items.
    ///
    /// - Parameters:
    ///   - runningPIDs: Processes that are currently running.
    ///   - fullScan: When `false`, only processes that owned a status item last time,
    ///     plus `alsoCheck`, are asked. A full scan asks every process (about 1.3 s for
    ///     160 processes on the development machine, almost all of it waiting on IPC).
    func statusItemFrames(runningPIDs: [pid_t], fullScan: Bool, alsoCheck: Set<pid_t> = []) async -> [CGRect] {
        await withCheckedContinuation { continuation in
            queue.async {
                let running = Set(runningPIDs)
                let targets = fullScan ? running : self.statusItemOwners.union(alsoCheck).intersection(running)
                var owners = fullScan ? Set<pid_t>() : self.statusItemOwners.intersection(running)
                var frames: [CGRect] = []
                for pid in targets {
                    let found = Self.extrasFrames(pid: pid)
                    if found.isEmpty {
                        owners.remove(pid)
                    } else {
                        owners.insert(pid)
                        frames += found
                    }
                }
                self.statusItemOwners = owners
                continuation.resume(returning: frames)
            }
        }
    }

    // MARK: Accessibility helpers

    private static func extrasFrames(pid: pid_t) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let extras: AXUIElement = attribute(app, "AXExtrasMenuBar") else { return [] }
        return childFrames(of: extras)
    }

    private static func childFrames(of element: AXUIElement) -> [CGRect] {
        guard let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return [] }
        return children.compactMap { child in
            guard let frame = frame(of: child), frame.width > 0, frame.height > 0 else { return nil }
            return frame
        }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute)
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
