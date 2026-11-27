import AppKit

/// Apps whose status items a menu bar manager keeps out of sight.
///
/// Dimble (bundle `app.fif7y.Pelmet`) hides status items without moving them: on macOS 27.2.1
/// Accessibility keeps reporting them at their places left of the drawn items, with no
/// attribute that tells them apart, so the right shape of Split stretched over the empty
/// space they leave. Dimble's own settings say which apps it hides.
nonisolated enum ConcealedStatusItems {
    static let dimbleBundleID = "app.fif7y.Pelmet"
    private static let dimbleSettingsKey = "app.fif7y.Pelmet.settings.v1"

    /// Bundle IDs of the apps whose status items Dimble hides; empty when Dimble is not
    /// running or its settings cannot be read.
    static func concealedBundleIDs(runningBundleIDs: Set<String>) -> Set<String> {
        guard runningBundleIDs.contains(dimbleBundleID) else { return [] }
        // Without this, a value cached in this process can outlive Dimble's later changes.
        CFPreferencesAppSynchronize(dimbleBundleID as CFString)
        guard
            let data = CFPreferencesCopyAppValue(dimbleSettingsKey as CFString, dimbleBundleID as CFString)
                as? Data
        else { return [] }
        return dimbleConcealedBundleIDs(settings: data)
    }

    /// Reads Dimble's settings (JSON). `sectionModel.assignments` alternates an item key and
    /// its section: `["bundle:com.raycast.macos", "alwaysHidden", ...]`. Both "hidden" and
    /// "alwaysHidden" are out of the menu bar until revealed. Keys of single items
    /// (`status:<bundle>::<name>`) are skipped, since the other items of that app may show.
    static func dimbleConcealedBundleIDs(settings: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: settings) as? [String: Any],
            let model = root["sectionModel"] as? [String: Any],
            let assignments = model["assignments"] as? [String]
        else { return [] }
        var concealed: Set<String> = []
        var index = 0
        while index + 1 < assignments.count {
            let key = assignments[index]
            let section = assignments[index + 1]
            index += 2
            guard section == "hidden" || section == "alwaysHidden", key.hasPrefix("bundle:") else { continue }
            concealed.insert(String(key.dropFirst("bundle:".count)))
        }
        return concealed
    }
}
