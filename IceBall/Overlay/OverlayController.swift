import AppKit
import Observation
import os

private let log = Logger(subsystem: "io.kkweb.IceBall", category: "Overlay")

/// Keeps one overlay panel per display in sync with the settings and the system state.
///
/// Work is driven by notifications. The only timer runs while Split is selected,
/// because macOS posts nothing when a status item changes width.
final class OverlayController {
    private let settings: SettingsStore
    private let regionReader = MenuBarRegionReader()
    private let wallpapers = WallpaperProvider()

    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var regions = MenuBarRegions()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var workspaceKVO: [NSKeyValueObservation] = []
    private let defaultsObserver = GlobalDefaultsObserver()
    private var splitRefreshTimer: Timer?
    private var splitRefreshTicks = 0
    private var appMenuRetryTask: Task<Void, Never>?
    private var spaceSettleTask: Task<Void, Never>?
    private var missingMenuBarTask: Task<Void, Never>?
    private var isRunning = false

    /// Whether the menu bar currently draws with a dark appearance. Set by the app delegate
    /// from the effective appearance of its own status item, which follows the menu bar.
    var menuBarIsDark = true {
        didSet { if menuBarIsDark != oldValue { layout() } }
    }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeSettings()
        installObservers()
        settingsDidChange()
    }

    /// Removes every overlay so the standard menu bar shows. Called on quit as well.
    func stop() {
        isRunning = false
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        workspaceKVO.removeAll()
        defaultsObserver.stop()
        stopSplitRefresh()
        wallpapers.stopWatching()
        removeAllPanels()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.configuration
            _ = settings.isEnabled
        } onChange: { [weak self] in
            // onChange fires before the new value is stored; apply on the next turn.
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.settingsDidChange()
                self.observeSettings()
            }
        }
    }

    private var isActive: Bool {
        settings.isEnabled && settings.configuration.shape != .standard
    }

    private func settingsDidChange() {
        if isActive && settings.configuration.shape == .split {
            startSplitRefresh()
        } else {
            stopSplitRefresh()
        }
        layout()
    }

    // MARK: Events

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        let distributed = DistributedNotificationCenter.default()

        func on(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor @Sendable (pid_t?) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                // Only the app's pid is needed; pull it out before hopping to the main actor.
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { handler(pid) }
            }
            observers.append((center, token))
        }

        on(local, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.expectedMenuBarCount = 0
            self?.wallpapers.invalidate()
            self?.layout()
            self?.refreshRegions(fullScan: false)
        }
        // Space switches, including entering and leaving full screen.
        on(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in
            self?.wallpapers.invalidate()
            self?.layout()
            self?.layoutAfterSpaceAnimation()
            self?.refreshApplicationMenu(retrying: true)
        }
        on(workspace, NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.wallpapers.invalidate()
            self?.layout()
            self?.refreshRegions(fullScan: true)
        }
        on(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] _ in
            self?.layout()
        }
        // New apps often add a status item a moment after launching.
        on(workspace, NSWorkspace.didLaunchApplicationNotification) { [weak self] pid in
            guard let pid else { return }
            self?.refreshStatusItemsAfterLaunch(of: pid)
        }
        on(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] _ in
            self?.refreshStatusItems(fullScan: false)
        }
        on(distributed, Notification.Name("AppleInterfaceThemeChangedNotification")) { [weak self] _ in
            self?.layout()
        }

        // The menu bar settings live in the global defaults domain; key-value observing
        // UserDefaults delivers changes made by System Settings (checked for _HIHideMenuBar).
        // The value read right after the callback can still be the old one, so read again
        // over the next few seconds.
        defaultsObserver.start(keys: SystemMenuBar.observedDefaultsKeys) { [weak self] in
            self?.wallpapers.invalidate()
            self?.layout()
            self?.layoutAfterDefaultsChange()
        }

        // An app switch also brings back a menu bar that macOS took off screen after a
        // wallpaper change (seen on macOS 27.2.1), so re-layout as well.
        workspaceKVO.append(NSWorkspace.shared.observe(\.menuBarOwningApplication) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.layout()
                self?.layoutAfterSpaceAnimation()
                self?.refreshApplicationMenu(retrying: true)
            }
        })
    }

    /// Windows can appear or vanish shortly after a notification (the full-screen backdrop
    /// during a space animation, the menu bar after an app switch); look again once settled.
    private func layoutAfterSpaceAnimation() {
        spaceSettleTask?.cancel()
        spaceSettleTask = Task { [weak self] in
            for delay in [300, 900] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.layout()
            }
        }
    }

    private var defaultsSettleTask: Task<Void, Never>?

    private func layoutAfterDefaultsChange() {
        defaultsSettleTask?.cancel()
        defaultsSettleTask = Task { [weak self] in
            for delay in [500, 1500, 3000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.layout()
            }
        }
    }

    // MARK: Region measurement (Split only)

    private func startSplitRefresh() {
        guard splitRefreshTimer == nil else { return }
        refreshRegions(fullScan: true)
        // A status item can change width (a clock, a percentage) without any notification.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.splitRefreshTicks += 1
                // A full scan once a minute catches status items added by apps that were already running.
                self.refreshRegions(fullScan: self.splitRefreshTicks % 12 == 0)
            }
        }
        timer.tolerance = 1.5
        RunLoop.main.add(timer, forMode: .common)
        splitRefreshTimer = timer
    }

    private func stopSplitRefresh() {
        splitRefreshTimer?.invalidate()
        splitRefreshTimer = nil
        appMenuRetryTask?.cancel()
        appMenuRetryTask = nil
        if regions != MenuBarRegions() {
            regions = MenuBarRegions()
        }
    }

    private var needsRegions: Bool {
        isActive && settings.configuration.shape == .split && MenuBarRegionReader.isTrusted
    }

    /// Also called after the Accessibility permission is granted.
    func refreshRegions(fullScan: Bool) {
        refreshApplicationMenu(retrying: false)
        refreshStatusItems(fullScan: fullScan)
    }

    /// After the frontmost app changes, its menus can take a moment to appear.
    private func refreshApplicationMenu(retrying: Bool) {
        log.debug("refresh app menu: needsRegions=\(self.needsRegions) trusted=\(MenuBarRegionReader.isTrusted)")
        guard needsRegions else { return }
        appMenuRetryTask?.cancel()
        let delays: [Duration] = retrying ? [.zero, .milliseconds(150), .milliseconds(500), .milliseconds(1500)] : [.zero]
        appMenuRetryTask = Task { [weak self] in
            for delay in delays {
                if delay > .zero { try? await Task.sleep(for: delay) }
                guard !Task.isCancelled, let self else { return }
                await self.measureApplicationMenu()
            }
        }
    }

    /// Each display's menu bar can show a different app (its frontmost window's app), so
    /// every display is measured on its own.
    private func measureApplicationMenu() async {
        var extents: [CGDirectDisplayID: CGFloat] = [:]
        for display in displayInfos() where display.hasMenuBar {
            let frames = await regionReader.applicationMenuFrames(atMenuBarOf: display.bounds)
            extents[display.displayID] = MenuBarRegions.applicationMenuExtent(frames: frames, on: display)
        }
        log.debug("app menu extents: \(String(describing: extents), privacy: .public)")
        guard needsRegions, regions.applicationMenuExtents != extents else { return }
        regions.applicationMenuExtents = extents
        layout()
    }

    private func refreshStatusItems(fullScan: Bool, alsoCheck: Set<pid_t> = []) {
        guard needsRegions else { return }
        let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        Task { [weak self] in
            guard let self else { return }
            let frames = await regionReader.statusItemFrames(runningPIDs: pids, fullScan: fullScan, alsoCheck: alsoCheck)
            let extent = MenuBarRegions.statusItemsExtent(frames: frames, displays: displayInfos())
            log.debug("status items: \(frames.count) frames, extent \(String(describing: extent), privacy: .public)")
            guard needsRegions, regions.statusItemsExtent != extent else { return }
            regions.statusItemsExtent = extent
            layout()
        }
    }

    private func refreshStatusItemsAfterLaunch(of pid: pid_t) {
        guard needsRegions else { return }
        Task { [weak self] in
            for delay in [1, 4] {
                try? await Task.sleep(for: .seconds(delay))
                self?.refreshStatusItems(fullScan: false, alsoCheck: [pid])
            }
        }
    }

    private func displayInfos() -> [MenuBarRegions.DisplayInfo] {
        let bars = SystemMenuBar.cgMenuBarFrames(from: SystemMenuBar.onScreenWindows())
        return NSScreen.screens.map { screen in
            let bounds = CGDisplayBounds(screen.displayID)
            let bar = bars.first { bounds.intersects($0) }
            return .init(
                displayID: screen.displayID,
                bounds: bounds,
                menuBarHeight: bar?.height ?? max(screen.safeAreaInsets.top, 24),
                hasMenuBar: bar != nil,
                notchXRange: screen.notchXRange
            )
        }
    }

    // MARK: Layout

    /// Recomputes every panel. Cheap: one window-list query plus arithmetic; drawing
    /// only happens for panels whose model actually changed.
    func layout() {
        layout(isRetry: false)
    }

    private func layout(isRetry: Bool) {
        // Any outside trigger restarts the back-off for a missing menu bar.
        if !isRetry { missingMenuBarChecks = 0 }
        // With "Automatically hide and show the menu bar" set to always, nothing is drawn and
        // the system bar slides in and out on its own, as Ice does. macOS 27 reports no
        // change when the hidden bar is revealed by the pointer.
        guard isRunning, isActive, !SystemMenuBar.autoHides else {
            log.debug("layout: inactive running=\(self.isRunning) active=\(self.isActive) autoHides=\(SystemMenuBar.autoHides)")
            removeAllPanels()
            wallpapers.stopWatching()
            return
        }

        let windows = SystemMenuBar.onScreenWindows()
        let bars = SystemMenuBar.cgMenuBarFrames(from: windows)
        let fullScreen = SystemMenuBar.fullScreenDisplayIDs(from: windows)
        let placement = Self.currentPlacement

        log.debug("layout: bars=\(bars.count) fullScreen=\(fullScreen.count, privacy: .public)")
        // The desktop picture is watched in both placements: above the bar it is painted,
        // and in both its brightness decides light or dark fill.
        wallpapers.startWatching { [weak self] in self?.layout() }

        // macOS takes the menu bar off screen while it rebuilds it (seen after a wallpaper
        // change and after turning auto-hide off, from 10 s to several minutes) and posts
        // nothing when it is back. Look again, with growing intervals, until it returns.
        let displaysWithBar = Set(NSScreen.screens.filter { screen in
            bars.contains { CGDisplayBounds(screen.displayID).intersects($0) }
        }.map(\.displayID))
        if displaysWithBar.count < expectedMenuBarCount {
            watchForMissingMenuBar()
        } else {
            missingMenuBarTask?.cancel()
            missingMenuBarTask = nil
            missingMenuBarChecks = 0
        }
        expectedMenuBarCount = max(expectedMenuBarCount, displaysWithBar.count)

        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = screen.displayID
            seen.insert(id)
            let displayBounds = CGDisplayBounds(id)
            // No menu bar on this display (another display has it, or it is hidden), or a
            // full-screen app: show nothing so the system state is untouched.
            guard !fullScreen.contains(id), let cgBar = bars.first(where: { displayBounds.intersects($0) }) else {
                hidePanel(for: id)
                continue
            }
            let bar = SystemMenuBar.cocoaRect(fromCG: cgBar)

            var wallpaper = wallpapers.image(for: screen, bar: bar)
            if placement == .aboveMenuBar {
                // Without the picture the shape cannot be cut out; fall back to the standard bar.
                if wallpaper == nil {
                    log.debug("layout: desktop picture for display \(id) not available yet or failed; showing the standard menu bar")
                    hidePanel(for: id)
                    continue
                }
            }

            // macOS draws menu titles light over a dark desktop picture and dark over a light
            // one; the status item's appearance does not follow (it stayed VibrantLight over
            // black on macOS 27.2.1). Judge from the picture's brightness under the bar.
            let isDark = wallpapers.luminance(for: screen, bar: bar).map { $0 < Self.darkLuminanceThreshold } ?? menuBarIsDark
            if placement == .belowMenuBar { wallpaper = nil }

            let barInView = CGRect(x: 0, y: OverlayPanel.shadowMargin, width: bar.width, height: bar.height)
            let shapes = ShapeLayout.rects(
                for: settings.configuration,
                in: barInView,
                leftExtent: regions.applicationMenuExtents[id],
                rightExtent: regions.statusItemsExtent
            )
            let model = OverlayDrawModel(
                bar: barInView,
                shapes: shapes,
                configuration: settings.configuration,
                isDark: isDark,
                placement: placement,
                wallpaper: wallpaper
            )

            let panel = panels[id] ?? makePanel(for: id)
            let frame = NSRect(x: bar.minX, y: bar.minY - OverlayPanel.shadowMargin, width: bar.width, height: bar.height + OverlayPanel.shadowMargin)
            if panel.frame != frame { panel.setFrame(frame, display: false) }
            if panel.level != placement.windowLevel { panel.level = placement.windowLevel }
            panel.overlayView.model = model
            if !panel.isVisible { panel.orderFrontRegardless() }
        }

        for id in panels.keys where !seen.contains(id) {
            panels.removeValue(forKey: id)?.close()
        }
    }

    /// The placement for the current system setting. `PlacementOverride` ("below" or
    /// "above") in the app's defaults overrides the detection, for when it is wrong.
    static var currentPlacement: OverlayPlacement {
        switch UserDefaults.standard.string(forKey: "PlacementOverride") {
        case "below": .belowMenuBar
        case "above": .aboveMenuBar
        default: SystemMenuBar.showsBackground ? .aboveMenuBar : .belowMenuBar
        }
    }

    /// How many menu bars were seen at once; reset when the display set changes.
    private var expectedMenuBarCount = 0

    private var missingMenuBarChecks = 0
    /// Below this average luminance of the desktop picture the menu bar is treated as dark.
    /// A guess at macOS's rule, not documented.
    static let darkLuminanceThreshold: CGFloat = 0.5
    /// Seconds between looks while a menu bar is missing: about 5 minutes in all.
    private static let missingMenuBarDelays: [Int] = [1, 2, 2, 3, 5, 5, 10, 10, 20, 30, 30, 60, 60, 60]

    private func watchForMissingMenuBar() {
        guard missingMenuBarTask == nil, missingMenuBarChecks < Self.missingMenuBarDelays.count else { return }
        let delay = Self.missingMenuBarDelays[missingMenuBarChecks]
        missingMenuBarChecks += 1
        missingMenuBarTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.missingMenuBarTask = nil
            self.layout(isRetry: true)
        }
    }

    private func makePanel(for id: CGDirectDisplayID) -> OverlayPanel {
        let panel = OverlayPanel(displayID: id)
        panels[id] = panel
        return panel
    }

    private func hidePanel(for id: CGDirectDisplayID) {
        panels[id]?.orderOut(nil)
    }

    private func removeAllPanels() {
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }
}

/// Calls back when any of the given keys changes in the defaults this process sees,
/// which include the global domain written by System Settings.
private final class GlobalDefaultsObserver: NSObject {
    private var keys: [String] = []
    private var handler: (() -> Void)?

    func start(keys: [String], handler: @escaping () -> Void) {
        stop()
        self.keys = keys
        self.handler = handler
        for key in keys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
    }

    func stop() {
        for key in keys {
            UserDefaults.standard.removeObserver(self, forKeyPath: key)
        }
        keys = []
        handler = nil
    }

    override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [weak self] in
            self?.handler?()
        }
    }
}
