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

    /// Processes known to own status items. Queue-confined.
    private var statusItemOwners = StatusItemOwners()
    /// When the menu bars started reading as unreadable for a status item scan. Queue-confined.
    private var menuBarsUnreadableSince: Double?

    /// Per-call timeout for Accessibility messages, so one hung app cannot stall a scan.
    private static let messagingTimeout: Float = 0.1

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Frames, in CG global coordinates, of the top-level menus shown in the menu bar of the
    /// display with CG bounds `displayBounds`; nil when the menu bar cannot be read now.
    func applicationMenuFrames(atMenuBarOf displayBounds: CGRect) async -> [CGRect]? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.menuBar(at: displayBounds).map(Self.childFrames))
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
    ///   - menuBars: CG bounds of the displays that show a menu bar.
    /// - Returns: nil, without asking anyone, when one of those menu bars cannot be read now,
    ///   for up to `MenuBarRegions.unreadableGrace` seconds. While Mission Control is open
    ///   many apps report no status items (seen on macOS 27.2.1: 13 of 20 owners), and such
    ///   a reading would only count against them. The limit keeps a frontmost app that never
    ///   answers Accessibility from stopping the scans.
    func statusItemFrames(
        runningPIDs: [pid_t], fullScan: Bool, alsoCheck: Set<pid_t> = [], menuBars: [CGRect]
    ) async -> [CGRect]? {
        await withCheckedContinuation { continuation in
            queue.async {
                let now = ProcessInfo.processInfo.systemUptime
                if menuBars.allSatisfy({ Self.menuBar(at: $0) != nil }) {
                    self.menuBarsUnreadableSince = nil
                } else {
                    let since = self.menuBarsUnreadableSince ?? now
                    self.menuBarsUnreadableSince = since
                    if now - since < MenuBarRegions.unreadableGrace {
                        continuation.resume(returning: nil)
                        return
                    }
                }
                let running = Set(runningPIDs)
                self.statusItemOwners.keepOnly(running: running)
                let targets = fullScan ? running : self.statusItemOwners.pids.union(alsoCheck).intersection(running)
                for pid in targets {
                    self.statusItemOwners.record(Self.extrasFrames(pid: pid), for: pid, at: now)
                }
                continuation.resume(returning: self.statusItemOwners.allFrames)
            }
        }
    }

    // MARK: Accessibility helpers

    /// The menu bar of the app shown at the left end of the menu bar of the display with CG
    /// bounds `displayBounds`. Hit-testing there tells which app it is showing. Nil when
    /// something else is there: with Mission Control open the hit lands on WindowManager,
    /// which has no menu bar (seen on macOS 27.2.1), and macOS posts nothing when it closes.
    private static func menuBar(at displayBounds: CGRect) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var hit: AXUIElement?
        var pid: pid_t = 0
        guard
            AXUIElementCopyElementAtPosition(
                systemWide, Float(displayBounds.minX + 5), Float(displayBounds.minY + 5), &hit) == .success,
            let hit, AXUIElementGetPid(hit, &pid) == .success
        else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return attribute(app, kAXMenuBarAttribute)
    }

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

/// The processes that own status items, with the frames last read from each.
///
/// Right after Mission Control closes, some apps still report no status items although the
/// menu bar can be read again (seen on macOS 27.2.1: 11 of 24 items left). Dropping them on
/// the first empty reading left the right shape too short until the next full scan, a minute
/// later. An owner that reads as empty keeps its last frames until it has had none for
/// `emptyGrace` seconds, which also ends items an app really removed. Counted in time, not
/// in scans, because launches and quits add scans in bursts.
nonisolated struct StatusItemOwners: Sendable {
    static let emptyGrace: Double = 10

    private(set) var framesByPID: [pid_t: [CGRect]] = [:]
    private var lastSeen: [pid_t: Double] = [:]

    var pids: Set<pid_t> { Set(framesByPID.keys) }
    var allFrames: [CGRect] { framesByPID.values.flatMap { $0 } }

    /// Forgets processes that quit.
    mutating func keepOnly(running: Set<pid_t>) {
        framesByPID = framesByPID.filter { running.contains($0.key) }
        lastSeen = lastSeen.filter { running.contains($0.key) }
    }

    /// - Parameter now: Seconds on a monotonic clock.
    mutating func record(_ frames: [CGRect], for pid: pid_t, at now: Double) {
        if !frames.isEmpty {
            framesByPID[pid] = frames
            lastSeen[pid] = now
        } else if let seen = lastSeen[pid], now - seen >= Self.emptyGrace {
            framesByPID[pid] = nil
            lastSeen[pid] = nil
        }
    }
}
