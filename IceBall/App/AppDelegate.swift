import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var overlay = OverlayController(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, overlay: overlay, checkForUpdates: { Updater.shared.checkNow() })

    private var appearanceObservation: NSKeyValueObservation?
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningInstance() { return }
        // The launch Apple event is only current here, so read it before anything else.
        let launchedAtLogin = Self.wasLaunchedAtLogin()

        started = true
        overlay.start()
        observeAppearance()
        updateMenuBarAppearance()
        Updater.shared.checkQuietly()
        #if DEBUG
            DebugSnapshot.scheduleIfRequested()
        #endif

        // With no Dock or menu bar icon, a launch by hand that showed nothing would look broken.
        // At login the window stays closed.
        if !launchedAtLogin { settingsWindow.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The system menu bar is never modified, so removing the overlays restores it fully.
        if started { overlay.stop() }
    }

    // There is no Dock icon and no menu bar icon: opening the app again from Finder or
    // Spotlight is how the settings window is reached.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    // MARK: Launch

    /// loginwindow marks the open-application event of a login launch, including one
    /// registered with `SMAppService.mainApp`.
    private static func wasLaunchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication
        else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
    }

    /// Two copies of the app at different paths (a build folder and Applications, say) are
    /// separate to Launch Services, and two instances would draw two sets of shapes. The later
    /// one opens the earlier one, which shows its settings window as on any reopen, and quits.
    private func handOffToRunningInstance() -> Bool {
        let current = NSRunningApplication.current
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let earlier = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != current.processIdentifier && !$0.isTerminated }
            .first { other in
                // If both start at once, only the later one gives way.
                guard let theirs = other.launchDate, let ours = current.launchDate else {
                    return other.processIdentifier < current.processIdentifier
                }
                return theirs < ours
                    || (theirs == ours && other.processIdentifier < current.processIdentifier)
            }
        guard let earlier, let url = earlier.bundleURL else { return false }

        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) {
            _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
        return true
    }

    // MARK: Menu bar appearance

    /// There is no status item, so the fallback for light or dark fill is the app's own
    /// appearance, which follows the system setting but not the desktop picture.
    private func observeAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateMenuBarAppearance() }
        }
    }

    private func updateMenuBarAppearance() {
        overlay.menuBarIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
