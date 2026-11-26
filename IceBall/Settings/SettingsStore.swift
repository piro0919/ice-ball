import Foundation
import Observation
import ServiceManagement

/// Owns the persisted settings. Every change is written to UserDefaults immediately.
@Observable
final class SettingsStore {
    var configuration: AppearanceConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            save()
        }
    }

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    /// Mirrors `SMAppService.mainApp.status`.
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered

    /// The last error from registering or unregistering the login item.
    private(set) var loginItemError: String?

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let configuration = "AppearanceConfiguration"
        static let isEnabled = "IsEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.configuration),
           let decoded = try? JSONDecoder().decode(AppearanceConfiguration.self, from: data) {
            configuration = decoded
        } else {
            configuration = .default
        }
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        refreshLoginItemStatus()
    }

    func resetToDefaults() {
        configuration = .default
    }

    private func save() {
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Keys.configuration)
        }
    }

    // MARK: Login item

    var launchesAtLogin: Bool {
        loginItemStatus == .enabled || loginItemStatus == .requiresApproval
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }

    func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }
}
