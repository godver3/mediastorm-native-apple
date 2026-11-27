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
    /// "Library copy": the server offers it first when the profile's libraries have the title,
    /// and Play takes the copy while it is the title's choice.
    static let library = "local"

    var offered: [QualityPreset]
    /// What Play uses now for the title on this device (its remembered preset, else the default).
    var movie: QualityPresetSelection
    var series: QualityPresetSelection
    /// What it would use without a remembered preset: picking it clears the title's memory.
    var movieDefault: QualityPresetSelection
    var seriesDefault: QualityPresetSelection
    /// The server's "Prefer library copies" switch; false: Play streams instead of taking a
    /// copy from the server's own libraries (nil from servers without it).
    var preferLibraryCopies: Bool?

    enum CodingKeys: String, CodingKey { case offered, movie, series, movieDefault, seriesDefault, preferLibraryCopies }

    init(offered: [QualityPreset], movie: QualityPresetSelection = .init(), series: QualityPresetSelection = .init(),
         movieDefault: QualityPresetSelection? = nil, seriesDefault: QualityPresetSelection? = nil,
         preferLibraryCopies: Bool? = nil) {
        self.offered = offered
        self.movie = movie
        self.series = series
        self.movieDefault = movieDefault ?? movie
        self.seriesDefault = seriesDefault ?? series
        self.preferLibraryCopies = preferLibraryCopies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offered = try c.decodeIfPresent([QualityPreset].self, forKey: .offered) ?? []
        movie = try c.decodeIfPresent(QualityPresetSelection.self, forKey: .movie) ?? .init()
        series = try c.decodeIfPresent(QualityPresetSelection.self, forKey: .series) ?? .init()
        movieDefault = try c.decodeIfPresent(QualityPresetSelection.self, forKey: .movieDefault) ?? movie
        seriesDefault = try c.decodeIfPresent(QualityPresetSelection.self, forKey: .seriesDefault) ?? series
        preferLibraryCopies = try c.decodeIfPresent(Bool.self, forKey: .preferLibraryCopies)
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

/// Which library copies Play takes, as the server decides for every other client.
enum LibraryCopyRule: Sendable {
    /// All of them: "Library copy" picked or the title's choice (and without presets, as before).
    case all
    /// Only Plex and Jellyfin copies: the server prefers streams over its own libraries' files.
    case remoteOnly
    /// None: another preset is picked for the title, so Play streams.
    case stream

    static func of(_ choices: QualityPresetChoices?, isMovie: Bool, picked: String?) -> LibraryCopyRule {
        guard let c = choices else { return .all }
        if c.preferLibraryCopies == false { return .remoteOnly }
        // Without a local copy the choice is not offered: picks are about ranking.
        guard c.offered(isMovie: isMovie).contains(where: { $0.id == QualityPresetChoices.library }) else { return .all }
        if let picked { return picked == QualityPresetChoices.library ? .all : .stream }
        return c.current(isMovie: isMovie).id == QualityPresetChoices.library ? .all : .stream
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
        // Kept without offered presets too when it switches library copies off (LibraryCopyRule).
        guard let choices: QualityPresetChoices = try? await send("GET", "/api/quality-presets", query: q),
              !choices.offered(isMovie: title.isMovie).isEmpty || choices.preferLibraryCopies == false else { return nil }
        return choices
    }
}
