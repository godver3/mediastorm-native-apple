import SwiftUI

/// Settings › Home Layout › Upcoming Episodes: this device's override of the profile's
/// `excludeUpcomingFromContinue` (nil follows the profile). Shown keeps a show whose next
/// episode airs within `ContinueWatchingItem.upcomingWindow` in Continue Watching; it stays
/// in My Upcoming either way.
@MainActor
final class UpcomingSettingsStore: ObservableObject {
    static let shared = UpcomingSettingsStore()

    @Published var showInContinueWatching: Bool? {
        didSet {
            defaults.set(showInContinueWatching, forKey: Self.key)
            // Home's Continue Watching rows rebuild with the new choice.
            NotificationCenter.default.post(name: .continueWatchingChanged, object: nil)
        }
    }

    /// The profile's value, as Home last loaded it, shown as "Default (…)".
    @Published private(set) var profileShows = false

    private let defaults = UserDefaults.standard
    private static let key = "homeLayout.upcomingInContinueWatching"

    private init() {
        _showInContinueWatching = Published(initialValue: defaults.object(forKey: Self.key) as? Bool)
    }

    func update(profileExcludes: Bool) {
        if profileShows != !profileExcludes { profileShows = !profileExcludes }
    }

    static let footer: LocalizedStringKey = "Shown keeps a show whose next episode airs within the next 7 days in Continue Watching; it stays in My Upcoming too. Hidden leaves it to My Upcoming. Saved on this device only."
}

extension HomeSettings {
    /// These settings with this device's Upcoming Episodes choice applied.
    @MainActor func applyingDeviceUpcoming() -> HomeSettings {
        let store = UpcomingSettingsStore.shared
        store.update(profileExcludes: excludeUpcomingFromContinue)
        var settings = self
        if let shows = store.showInContinueWatching { settings.excludeUpcomingFromContinue = !shows }
        return settings
    }
}
