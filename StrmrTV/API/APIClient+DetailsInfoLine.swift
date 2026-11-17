import Foundation

extension APIClient {
    /// The details page's optional info line under the actions (`display.showDetails*`):
    /// the prequeued release's name and the tracks Play will use. Layered as
    /// `episodePrivacy()`: this device's override from `/api/clients/{id}/settings`
    /// (top-level there), then the profile's display settings. Nil members when neither answers.
    struct DetailsInfoLine: Equatable {
        var showFilename: Bool?
        var showSelectedTracks: Bool?
    }

    func detailsInfoLine() async -> DetailsInfoLine {
        struct Values: Decodable {
            let showDetailsPrequeueFilename: Bool?
            let showDetailsSelectedTracks: Bool?
        }
        struct UserSettings: Decodable { let display: Values? }

        async let user: UserSettings? = try? await send("GET", "/api/users/\(Self.segment(profileID))/settings",
                                                        promptOnLock: false, timeout: 10)
        async let device: Values? = try? await send("GET", "/api/clients/\(Self.segment(Config.clientID))/settings",
                                                    query: ["userId": profileID], promptOnLock: false, timeout: 10)
        let (u, d) = await (user?.display, device)
        return DetailsInfoLine(
            showFilename: d?.showDetailsPrequeueFilename ?? u?.showDetailsPrequeueFilename,
            showSelectedTracks: d?.showDetailsSelectedTracks ?? u?.showDetailsSelectedTracks)
    }
}

/// The details info line's settings: this device's overrides (Settings › Details; nil follows
/// the server), else the profile's `APIClient.DetailsInfoLine`, refreshed whenever a details
/// page or Settings appears. All off until read.
@MainActor
final class DetailsInfoLineStore: ObservableObject {
    static let shared = DetailsInfoLineStore()

    @Published var filename: Bool? { didSet { store(filename, Keys.filename) } }
    @Published var selectedTracks: Bool? { didSet { store(selectedTracks, Keys.tracks) } }

    /// The profile's values, shown as "Default (…)"; nil members until read.
    @Published private(set) var server = APIClient.DetailsInfoLine()

    var showFilename: Bool { filename ?? server.showFilename ?? false }
    var showSelectedTracks: Bool { selectedTracks ?? server.showSelectedTracks ?? false }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let filename = "strmrtv.detailsInfoFilename"
        static let tracks = "strmrtv.detailsInfoSelectedTracks"
    }

    private init() {
        filename = defaults.object(forKey: Keys.filename) as? Bool
        selectedTracks = defaults.object(forKey: Keys.tracks) as? Bool
    }

    func refresh() async {
        let fresh = await APIClient.shared.detailsInfoLine()
        if fresh != server { server = fresh }
    }

    private func store(_ value: Bool?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
