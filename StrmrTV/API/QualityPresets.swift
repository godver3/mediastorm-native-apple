import Foundation

/// Quality presets (servers with Sonarr/Radarr-style presets): the presets a version picker
/// offers for a title and which one Play uses. Shapes match the backend's
/// `GET /api/quality-presets` (handlers/quality_presets_selection.go `clientPresetList`), as
/// the web client's `api/qualityPresets.ts` reads them.
struct QualityPreset: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// "movie", "series", or empty for the simple ranking, which fits both.
    let mediaType: String?
}

struct QualityPresetSelection: Decodable, Hashable, Sendable {
    /// Empty when the simple ranking applies.
    var presetId: String?
    var name: String?
    /// Where it comes from (title, device, profile, server, …).
    var source: String?

    /// The offered preset this selection names ("simple" for the simple ranking).
    var id: String { presetId.flatMap { $0.isEmpty ? nil : $0 } ?? QualityPresetChoices.simple }
}

struct QualityPresetChoices: Decodable, Hashable, Sendable {
    /// The ID the server uses for its simple ranking (no preset).
    static let simple = "simple"

    var offered: [QualityPreset]
    /// What Play uses now for the title on this device (its remembered preset, else the default).
    var movie: QualityPresetSelection
    var series: QualityPresetSelection
    /// What it would use without a remembered preset: picking it clears the title's memory.
    var movieDefault: QualityPresetSelection
    var seriesDefault: QualityPresetSelection

    enum CodingKeys: String, CodingKey { case offered, movie, series, movieDefault, seriesDefault }

    init(offered: [QualityPreset], movie: QualityPresetSelection = .init(), series: QualityPresetSelection = .init(),
         movieDefault: QualityPresetSelection? = nil, seriesDefault: QualityPresetSelection? = nil) {
        self.offered = offered
        self.movie = movie
        self.series = series
        self.movieDefault = movieDefault ?? movie
        self.seriesDefault = seriesDefault ?? series
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offered = try c.decodeIfPresent([QualityPreset].self, forKey: .offered) ?? []
        movie = try c.decodeIfPresent(QualityPresetSelection.self, forKey: .movie) ?? .init()
        series = try c.decodeIfPresent(QualityPresetSelection.self, forKey: .series) ?? .init()
        movieDefault = try c.decodeIfPresent(QualityPresetSelection.self, forKey: .movieDefault) ?? movie
        seriesDefault = try c.decodeIfPresent(QualityPresetSelection.self, forKey: .seriesDefault) ?? series
    }

    /// The presets offered for a movie or a series, in the server's order.
    func offered(isMovie: Bool) -> [QualityPreset] {
        offered.filter { ($0.mediaType ?? "").isEmpty || $0.mediaType == (isMovie ? "movie" : "series") }
    }

    func current(isMovie: Bool) -> QualityPresetSelection { isMovie ? movie : series }
    func defaultSelection(isMovie: Bool) -> QualityPresetSelection { isMovie ? movieDefault : seriesDefault }

    /// The preset Play uses: a pick made this session, else the server's current one.
    func activeID(isMovie: Bool, picked: String?) -> String { picked ?? current(isMovie: isMovie).id }

    /// The active preset's name, for "Quality: <name>".
    func activeName(isMovie: Bool, picked: String?) -> String {
        let id = activeID(isMovie: isMovie, picked: picked)
        if let preset = offered(isMovie: isMovie).first(where: { $0.id == id }) { return preset.name }
        let current = current(isMovie: isMovie)
        if current.id == id, let name = current.name, !name.isEmpty { return name }
        return id == Self.simple ? String(localized: "Simple") : id
    }

    /// The Quality action's label.
    func label(isMovie: Bool, picked: String?) -> String {
        String(localized: "Quality: \(activeName(isMovie: isMovie, picked: picked))")
    }
}

extension SourceResult {
    /// The preset's *arr quality ("WEB-2160p") when a preset ranked this result.
    var arrQuality: String? { attributes["arrQuality"].flatMap { $0.isEmpty ? nil : $0 } }
    /// The custom-format score when a preset ranked this result.
    var customFormatScore: Int? { attributes["customFormatScore"].flatMap(Int.init) }
    /// The preset that ranked this result.
    var qualityPresetName: String? { attributes["qualityPreset"].flatMap { $0.isEmpty ? nil : $0 } }
    /// Rejected only by the active quality preset (`includeFiltered`): still playable, listed
    /// under Other qualities.
    var isOtherQuality: Bool { (raw["filterReason"] as? String)?.hasPrefix("quality preset:") ?? false }
    /// Rejected by another filter (identity, size, …): not shown.
    var isFiltered: Bool { (raw["filterStatus"] as? String) == "filtered" }
}

extension APIClient {
    /// The quality presets offered for `title` on this profile and device, or nil when the
    /// server has none to offer for it (no presets, an older server, or an error).
    func qualityPresets(for title: DetailsTarget) async -> QualityPresetChoices? {
        var q = ["userId": profileID, "clientId": Config.clientID, "mediaType": title.isMovie ? "movie" : "series",
                 "titleId": title.titleID, "name": title.name]
        if let v = title.imdbID { q["imdbId"] = v }
        if let v = title.tmdbID { q["tmdbId"] = v }
        if let v = title.tvdbID { q["tvdbId"] = v }
        if let v = title.year { q["year"] = String(v) }
        guard let choices: QualityPresetChoices = try? await send("GET", "/api/quality-presets", query: q),
              !choices.offered(isMovie: title.isMovie).isEmpty else { return nil }
        return choices
    }
}
