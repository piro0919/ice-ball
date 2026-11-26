import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = SettingsStore()
    private lazy var overlay = OverlayController(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, overlay: overlay)

    private var statusItem: NSStatusItem?
    private var enabledMenuItem: NSMenuItem?
    private var statusItemObservations: [NSKeyValueObservation] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        overlay.start()
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

    // Opening the app again from Finder or Spotlight shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Ice Ball")
        item.autosaveName = "IceBallStatusItem"

        let menu = NSMenu()
        menu.delegate = self
        let enabled = NSMenuItem(title: L.enableAppearance, action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        menu.addItem(enabled)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let updatesItem = NSMenuItem(title: L.checkForUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
        enabledMenuItem = enabled

        // The status item's button takes the menu bar's light/dark appearance, which on
        // macOS 26+ depends on the desktop picture, not only on the system setting.
        if let button = item.button {
            statusItemObservations.append(
                button.observe(\.effectiveAppearance) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.updateMenuBarAppearance() }
                })
        }
    }

    private func updateMenuBarAppearance() {
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        overlay.menuBarIsDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func menuWillOpen(_ menu: NSMenu) {
        enabledMenuItem?.state = settings.isEnabled ? .on : .off
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
    }

    @objc private func checkForUpdates() {
        Updater.shared.checkNow()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
