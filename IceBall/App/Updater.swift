import AppKit
import Sparkle

/// Automatic updates through Sparkle, set up like the other kkweb Mac apps.
///
/// It checks once at launch and never on a timer. When an update is found, Sparkle's window
/// asks whether to install it. `SUEnableAutomaticChecks` is false in Info.plist so that Sparkle
/// does not ask on first launch whether it may check automatically.
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    /// Whether the quiet check at launch found an update. The window is shown once the check ends.
    private var foundUpdate = false

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

    /// The check at launch. Says nothing when there is no update.
    func checkQuietly() {
        // Local builds are 0.0.0 and would always find a "newer" version.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version != "0.0.0" else { return }
        controller.updater.checkForUpdateInformation()
    }

    /// "Check for Updates…". Shows the result even when the app is up to date.
    func checkNow() {
        NSApp.activate()
        controller.updater.checkForUpdates()
    }

    // MARK: SPUUpdaterDelegate

    /// A window requested during the quiet check is dropped by Sparkle, so remember the
    /// result and ask again once the check has finished.
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { foundUpdate = true }
    }

    nonisolated func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            // Only after the quiet check. Closing the window opened by checkNow also lands here
            // with an update found; showing it again then would reopen it every time it closes.
            guard updateCheck == .updateInformation, foundUpdate else { return }
            foundUpdate = false
            DispatchQueue.main.async { [weak self] in self?.checkNow() }
        }
    }
}
