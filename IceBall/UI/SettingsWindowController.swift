import AppKit
import ScreenCaptureKit
import SwiftUI

/// Hosts the SwiftUI settings view in an ordinary window, since the app has no Dock
/// icon or main menu from which a SwiftUI `Settings` scene could be opened.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let overlay: OverlayController
    private let permissions = PermissionState()
    private let previewMetrics = PreviewMetrics()
    private var window: NSWindow?

    init(settings: SettingsStore, overlay: OverlayController) {
        self.settings = settings
        self.overlay = overlay
        super.init()
        permissions.onGranted = { [weak overlay] in overlay?.refreshRegions(fullScan: true) }
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        settings.refreshLoginItemStatus()
        permissions.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(settings: settings, permissions: permissions, previewMetrics: previewMetrics)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Ice Ball 設定"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        settings.refreshLoginItemStatus()
        permissions.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        permissions.stopWatching()
    }
}

/// Tracks the permissions: Accessibility (Split only) and Screen Recording (only when the
/// overlay must sit above a menu bar that shows its background).
@Observable
final class PermissionState {
    private(set) var isAccessibilityTrusted = MenuBarRegionReader.isTrusted
    private(set) var hasScreenCapturePermission = WallpaperProvider.hasScreenCapturePermission
    /// Whether the overlay has to sit above the menu bar and therefore needs the desktop picture.
    private(set) var needsDesktopPicture = OverlayController.currentPlacement == .aboveMenuBar
    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored var onGranted: (() -> Void)?

    func refresh() {
        let trusted = MenuBarRegionReader.isTrusted
        if trusted && !isAccessibilityTrusted { onGranted?() }
        isAccessibilityTrusted = trusted
        hasScreenCapturePermission = WallpaperProvider.hasScreenCapturePermission
        needsDesktopPicture = OverlayController.currentPlacement == .aboveMenuBar
        if trusted { stopWatching() }
    }

    /// Shows the system prompt and then checks once a second until permission is granted
    /// or the settings window closes. There is no public notification for this change.
    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        guard watchTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    /// `CGRequestScreenCaptureAccess()` does not prompt on macOS 15+ (noted in Ice's
    /// `ScreenCapture.requestPermissions`); asking ScreenCaptureKit for content does.
    func requestScreenCapture() {
        SCShareableContent.getWithCompletionHandler { _, _ in }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
    }
}
