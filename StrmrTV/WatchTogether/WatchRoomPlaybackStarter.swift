import Foundation

/// The lobby starts the room's playback itself (as the Android app does): it loads the title's
/// details in the background and plays the room's episode when it names one (the host's), else
/// what Play would play there (the movie, or the series' up-next episode), at the room's
/// position. Closing the player lands back on the lobby. A guest's player also comes back here
/// to switch to the host's new episode.
@MainActor
enum WatchRoomPlaybackStarter {
    static func play(_ room: WatchRoom, profileID: String) async throws {
        PlaybackCoordinator.shared.play(try await request(for: room, profileID: profileID))
    }

    /// The playback `play` starts, without starting it.
    static func request(for room: WatchRoom, profileID: String) async throws -> PlaybackRequest {
        let target = room.detailsTarget
        let bundle = try await APIClient.shared.detailsBundle(target)
        let launch = WatchRoomLaunch(roomID: room.id, itemID: room.itemId, isHost: room.isHost(profileID),
                                     position: room.position > 0 ? room.position : nil)
        var title: Title?
        var seasons: [Season] = []
        var episode: Episode?
        if target.isMovie {
            title = bundle.movieDetails
        } else if let details = bundle.seriesDetails {
            title = details.title
            seasons = details.seasons
            episode = room.episode.flatMap { find($0, in: details.seasons) }
                ?? DetailsView.findPrimaryEpisode(in: details.seasons, upNext: bundle.upNextEpisode)
            guard episode != nil else { throw APIError.notReady(String(localized: "No episode to play")) }
        }
        // The room's position wins; a host opening a fresh room starts from its own resume point,
        // which the sync then seeds into the room.
        let start: StartPoint? = launch.position.map { .seconds($0) }
            ?? (launch.isHost ? (episode?.resume?.startPoint ?? bundle.resume?.startPoint) : nil)
        var request = DetailsRequest.make(target: target, title: title, seasons: seasons, episode: episode,
                                          start: start, seed: .random(in: .min ... .max), library: nil)
        request.watchRoom = launch
        return request
    }

    static func find(_ wanted: WatchRoomEpisode, in seasons: [Season]) -> Episode? {
        for season in seasons {
            if let match = season.episodes.first(where: {
                $0.seasonNumber == wanted.seasonNumber && $0.episodeNumber == wanted.episodeNumber
            }) { return match }
        }
        return nil
    }
}

extension WatchRoomEpisode {
    init(_ episode: Episode) {
        self.init(seasonNumber: episode.seasonNumber, episodeNumber: episode.episodeNumber,
                  episodeId: episode.itemId ?? episode.id, title: episode.name)
    }

    init(_ info: PlaybackRequest.EpisodeInfo) {
        self.init(seasonNumber: info.season, episodeNumber: info.episode, episodeId: info.itemID, title: info.name)
    }
}
