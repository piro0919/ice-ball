import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var overlay = OverlayController(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, overlay: overlay, checkForUpdates: { Updater.shared.checkNow() })

    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.start()
        observeAppearance()
        updateMenuBarAppearance()
        Updater.shared.checkQuietly()
        #if DEBUG
            DebugSnapshot.scheduleIfRequested()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The system menu bar is never modified, so removing the overlays restores it fully.
        overlay.stop()
    }

    // There is no Dock icon and no menu bar icon: opening the app again from Finder or
    // Spotlight is how the settings window is reached.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
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
