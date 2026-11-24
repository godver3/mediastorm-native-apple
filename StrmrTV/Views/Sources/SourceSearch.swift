import Foundation

/// The manual source list's search, order and health, shared by the details page's source
/// picker and the player's Switch Source list, so the two show the same
/// sources in the same order.
///
/// Both lists used to run their own `/api/indexers/search`, minutes apart: the indexers, the
/// remembered usenet health and the adaptive caps can change between the two, so the
/// server's ranking (and its order among equal ranks) came back different. Now the picker's
/// latest results are kept per title / episode, and Switch Source shows those, in the same
/// `ordered` order with the same health; it searches itself only when the picker hasn't
/// searched in the last `maxAge`.
@MainActor
enum SourceSearch {
    struct Key: Hashable {
        let titleID: String
        let query: String
        /// The episode's ordering: "S01E02" is a different episode in each.
        var ordering: String? = nil
    }

    struct Snapshot {
        var results: [SourceResult]
        var health: [Int: SourceHealth]
        let at: Date
    }

    /// How long a search is reused by Switch Source.
    static let maxAge: TimeInterval = 30 * 60
    private static var snapshots: [Key: Snapshot] = [:]

    /// The search query ("Name S01E02", or "Name 2024").
    nonisolated static func query(name: String, year: Int?, episode: (season: Int, episode: Int)?) -> String {
        if let episode { return name + String(format: " S%02dE%02d", episode.season, episode.episode) }
        if let year { return "\(name) \(year)" }
        return name
    }

    /// The list's order: the server's rank (its response order), the one order both lists use.
    nonisolated static func ordered(_ results: [SourceResult]) -> [SourceResult] {
        results.sorted { $0.index < $1.index }
    }

    /// The health a result starts with: the search's own annotation.
    nonisolated static func initialHealth(_ results: [SourceResult]) -> [Int: SourceHealth] {
        Dictionary(results.compactMap { r in r.health.map { (r.index, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Searches and keeps the results for this title / episode (the source picker, and
    /// Switch Source when nothing recent is kept).
    static func search(title: DetailsTarget, query: String, numbering: EpisodeNumbering? = nil) async throws -> [SourceResult] {
        let presets = QualityPresetStore.shared
        let picked = presets.picked(titleID: title.titleID)
        let ranked = presets.activePresetName(title) != nil
        let api = APIClient.shared
        let found: [SourceResult]
        do {
            found = try await api.searchSources(query: query, title: title, numbering: numbering,
                                                qualityPreset: picked, includeFiltered: ranked)
        } catch where picked != nil && QualityPresetStore.isPresetRefusal(error) {
            // The picked preset is no longer offered: search with the title's default.
            presets.reject(titleID: title.titleID)
            found = try await api.searchSources(query: query, title: title, numbering: numbering, includeFiltered: ranked)
        }
        let results = ordered(found)
        snapshots[Key(titleID: title.titleID, query: query, ordering: numbering?.ordering)] =
            Snapshot(results: results, health: initialHealth(results), at: Date())
        return results
    }

    /// Drops the title's kept results (a quality preset was picked, so they rank differently).
    static func forget(titleID: String) {
        snapshots = snapshots.filter { $0.key.titleID != titleID }
    }

    /// The preset that ranked `results`, for the list's "Ranked by" header.
    nonisolated static func rankedBy(_ results: [SourceResult]) -> String? {
        results.lazy.compactMap(\.qualityPresetName).first
    }

    /// The results kept for this title / episode, if recent enough.
    static func recent(title: DetailsTarget, query: String, numbering: EpisodeNumbering? = nil,
                       now: Date = Date()) -> Snapshot? {
        guard let snapshot = snapshots[Key(titleID: title.titleID, query: query, ordering: numbering?.ordering)],
              now.timeIntervalSince(snapshot.at) < maxAge else { return nil }
        return snapshot
    }

    /// Records a result's latest health (a resolved check or a probe), so the other list
    /// shows it too.
    static func updateHealth(title: DetailsTarget, query: String, numbering: EpisodeNumbering? = nil,
                             index: Int, health: SourceHealth) {
        snapshots[Key(titleID: title.titleID, query: query, ordering: numbering?.ordering)]?.health[index] = health
    }
}
