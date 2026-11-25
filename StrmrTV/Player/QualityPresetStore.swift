import Foundation

/// The quality presets offered per title, and the presets picked on details pages this session
/// (per profile and title), as the web client's `pickedPresets`. The server remembers a pick for
/// the profile, device and title once a prequeue sends it; until the app relaunches the pick is
/// also sent on the title's prequeues and source searches, so a search can't rank with the old
/// one in between.
@MainActor
final class QualityPresetStore: ObservableObject {
    static let shared = QualityPresetStore()

    @Published private(set) var choices: [String: QualityPresetChoices] = [:]
    @Published private(set) var picked: [String: String] = [:]
    /// Loads still running, so Play can wait for them (`awaitLoad`).
    private var loading: [String: Task<QualityPresetChoices?, Never>] = [:]

    private func key(_ titleID: String, profile: String) -> String { profile + "|" + titleID }

    /// Loads the offered presets for `title` (nil hides the Quality action).
    func load(_ title: DetailsTarget) async {
        let profile = APIClient.shared.profileID
        let k = key(title.titleID, profile: profile)
        let task = Task { await APIClient.shared.qualityPresets(for: title) }
        loading[k] = task
        let loaded = await task.value
        if let loaded { choices[k] = loaded } else { choices[k] = nil }
        if loading[k] == task { loading[k] = nil }
    }

    /// Whether `title`'s presets are still loading.
    func isLoading(_ title: DetailsTarget) -> Bool {
        loading[key(title.titleID, profile: APIClient.shared.profileID)] != nil
    }

    /// Waits, up to `timeout`, for `title`'s presets to load (they say whether Play takes a
    /// library copy).
    func awaitLoad(_ title: DetailsTarget, timeout: Duration = .seconds(5)) async {
        // Polled: awaiting the load's task would not stop at the timeout (it ignores cancellation).
        let deadline = ContinuousClock.now + timeout
        while isLoading(title), ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The choices for `title` when the server offers it presets (nil hides the Quality action).
    func choices(for title: DetailsTarget) -> QualityPresetChoices? {
        guard let c = choices[key(title.titleID, profile: APIClient.shared.profileID)],
              !c.offered(isMovie: title.isMovie).isEmpty else { return nil }
        return c
    }

    /// Which library copies Play takes for `title` (all of them while its presets load).
    func libraryRule(for title: DetailsTarget) -> LibraryCopyRule {
        LibraryCopyRule.of(choices[key(title.titleID, profile: APIClient.shared.profileID)],
                           isMovie: title.isMovie, picked: picked(titleID: title.titleID))
    }

    /// The preset picked for the title this session, sent with its prequeues and searches.
    func picked(titleID: String, profile: String = APIClient.shared.profileID) -> String? {
        picked[key(titleID, profile: profile)]
    }

    /// The preset Play uses for `title`, when one (not the simple ranking) ranks it.
    func activePresetName(_ title: DetailsTarget) -> String? {
        guard let c = choices(for: title) else { return nil }
        let id = c.activeID(isMovie: title.isMovie, picked: picked(titleID: title.titleID))
        // "Library copy" ranks nothing either: a failed stream is not its doing.
        return id == QualityPresetChoices.simple || id == QualityPresetChoices.library
            ? nil : c.activeName(isMovie: title.isMovie, picked: picked(titleID: title.titleID))
    }

    /// Picks `id` for `title`: restarts the page's warm prequeue with it (the server then
    /// remembers it, or forgets the title's memory for the default) and drops Choose Source's
    /// kept results, which were ranked with the old preset.
    func pick(_ id: String, for title: DetailsTarget) {
        guard let c = choices(for: title),
              id != c.activeID(isMovie: title.isMovie, picked: picked(titleID: title.titleID)) else { return }
        picked[key(title.titleID, profile: APIClient.shared.profileID)] = id
        SourceSearch.forget(titleID: title.titleID)
        PlaybackCoordinator.shared.restartWarm(title)
    }

    /// The server refused the picked preset (400/403: no longer offered or allowed): go back to
    /// the title's default.
    func reject(titleID: String, profile: String = APIClient.shared.profileID) {
        picked[key(titleID, profile: profile)] = nil
    }

    /// Play failed with a preset ranking the title: say why and where the other releases are.
    func explain(_ error: Error, title: DetailsTarget) -> Error {
        guard let name = activePresetName(title) else { return error }
        return APIError.notReady(String(localized:
            "No release matched the quality preset “\(name)”. Other qualities are listed in Choose Source, or pick another preset under Quality."))
    }

    /// Whether `error` is the server refusing a requested preset.
    nonisolated static func isPresetRefusal(_ error: Error) -> Bool {
        guard let status = (error as? APIError)?.statusCode else { return false }
        return status == 400 || status == 403
    }
}
