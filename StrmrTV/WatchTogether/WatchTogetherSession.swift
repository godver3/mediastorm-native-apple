import Foundation

/// A watch room's playback on this device: the lobby's request carries it to the player, which
/// follows the room (`WatchRoomPlaybackSync`).
struct WatchRoomLaunch: Hashable, Sendable {
    let roomID: String
    /// The room's title (`WatchRoom.itemId`), for the player's item-mismatch check.
    let itemID: String
    let isHost: Bool
    /// The room's position when the lobby opened the title; nil starts where details would.
    let position: Double?
    /// The lobby opened this player: a host's resume point may seed the room. A replacement for
    /// the same episode (source switch, Auto Switch) or the next episode never seeds.
    var seedsResume = true

    /// The same room for a player that replaces this one.
    var replacement: WatchRoomLaunch {
        var next = WatchRoomLaunch(roomID: roomID, itemID: itemID, isHost: isHost, position: nil)
        next.seedsResume = false
        return next
    }
}

/// The device's Watch Together state, shared by both platforms: the active room for the current
/// profile (persisted per profile, validated on launch) and the player closing.
@MainActor
final class WatchTogetherSession: ObservableObject {
    static let shared = WatchTogetherSession()
    private static let log = AppLog(category: "watch-together")

    /// The room this profile is in, if any.
    @Published private(set) var activeRoomID: String?
    /// Bumped when a watch-room player closes (the lobby underneath shows again).
    @Published private(set) var playerClosedCount = 0
    private var restoreTask: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private struct Saved: Codable {
        let roomId: String
        let itemId: String?
    }

    private static func key(_ profileID: String) -> String { "strmr.watchTogether.activeRoom.\(profileID)" }

    private var profileID: String { APIClient.shared.profileID }

    /// Remembers (or, with nil, forgets) the profile's active room.
    func setActive(_ room: WatchRoom?) {
        setActive(roomID: room.flatMap { $0.isEnded ? nil : $0.id }, itemID: room?.itemId)
    }

    func setActive(roomID: String?, itemID: String?, profile: String? = nil) {
        let key = Self.key(profile ?? profileID)
        if let roomID {
            let data = try? JSONEncoder().encode(Saved(roomId: roomID, itemId: itemID))
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        if profile == nil || profile == profileID, activeRoomID != roomID { activeRoomID = roomID }
    }

    func savedRoom(profile: String) -> (roomID: String, itemID: String?)? {
        guard let data = defaults.data(forKey: Self.key(profile)),
              let saved = try? JSONDecoder().decode(Saved.self, from: data), !saved.roomId.isEmpty else { return nil }
        return (saved.roomId, saved.itemId)
    }

    /// On launch (and a profile switch): checks the saved room still exists for this profile and
    /// forgets it if it ended or is no longer ours. A network failure retries every 10 s while
    /// the profile stays the same. No navigation: Home's Watch Together row leads back to it.
    func restore() {
        restoreTask?.cancel()
        let profile = profileID
        guard let saved = savedRoom(profile: profile) else {
            activeRoomID = nil
            return
        }
        activeRoomID = saved.roomID
        restoreTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let room = try await APIClient.shared.watchRoom(saved.roomID)
                    guard let self, profile == self.profileID else { return }
                    if room.isEnded || (saved.itemID.map { $0 != room.itemId } ?? false) {
                        Self.log.notice("saved room \(saved.roomID) is over; forgetting it")
                        self.setActive(roomID: nil, itemID: nil, profile: profile)
                    } else {
                        Self.log.notice("saved room \(saved.roomID) restored (\(room.statusRaw))")
                        self.setActive(roomID: room.id, itemID: room.itemId, profile: profile)
                    }
                    return
                } catch let error as APIError where error.dropsSavedWatchRoom {
                    self?.setActive(roomID: nil, itemID: nil, profile: profile)
                    return
                } catch is CancellationError {
                    return
                } catch {
                    Self.log.error("restoring room \(saved.roomID) failed: \(error.localizedDescription); retrying in 10 s")
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    func watchRoomPlayerClosed() {
        playerClosedCount += 1
    }
}

extension WatchRoom {
    /// The details page the room is for, from the params it was created with (the Expo
    /// app's details-route params), falling back to the room's own fields.
    var detailsTarget: DetailsTarget {
        func param(_ key: String) -> String? { params[key].flatMap { $0.isEmpty ? nil : $0 } }
        return DetailsTarget(
            titleID: param("titleId") ?? itemId,
            name: param("title") ?? title,
            isMovie: (param("mediaType") ?? mediaType) == "movie",
            year: param("year").flatMap { Int($0) },
            tmdbID: param("tmdbId"), imdbID: param("imdbId"), tvdbID: param("tvdbId"),
            posterURL: param("posterUrl") ?? posterUrl, textPosterURL: nil,
            backdropURL: param("backdropUrl") ?? backdropUrl,
            logoURL: param("logoUrl"), overview: param("description"))
    }

    /// The details-route params a new room is created with (the Expo app's, so its clients
    /// can open the title too).
    static func params(for target: DetailsTarget, logoURL: String?, overview: String?) -> [String: String] {
        let backdrop = target.backdropURL ?? ""
        return [
            "title": target.name, "titleId": target.titleID, "mediaType": target.isMovie ? "movie" : "series",
            "description": overview ?? target.overview ?? "", "headerImage": backdrop.isEmpty ? (target.posterURL ?? "") : backdrop,
            "posterUrl": target.posterURL ?? "", "logoUrl": logoURL ?? target.logoURL ?? "", "backdropUrl": backdrop,
            "year": target.year.map(String.init) ?? "", "tmdbId": target.tmdbID ?? "", "imdbId": target.imdbID ?? "",
            "tvdbId": target.tvdbID ?? "",
        ]
    }
}
