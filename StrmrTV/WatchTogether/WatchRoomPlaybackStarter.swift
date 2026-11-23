import Foundation

/// The lobby starts the room's playback itself (as the Android app does): it loads the title's
/// details in the background and plays what Play would play there (the movie, or the series'
/// up-next episode), at the room's position. Closing the player lands back on the lobby.
@MainActor
enum WatchRoomPlaybackStarter {
    static func play(_ room: WatchRoom, profileID: String) async throws {
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
            episode = DetailsView.findPrimaryEpisode(in: details.seasons, upNext: bundle.upNextEpisode)
            guard episode != nil else { throw APIError.notReady(String(localized: "No episode to play")) }
        }
        // The room's position wins; a host opening a fresh room starts from its own resume point,
        // which the sync then seeds into the room.
        let start: StartPoint? = launch.position.map { .seconds($0) }
            ?? (launch.isHost ? (episode?.resume?.startPoint ?? bundle.resume?.startPoint) : nil)
        var request = DetailsRequest.make(target: target, title: title, seasons: seasons, episode: episode,
                                          start: start, seed: .random(in: .min ... .max), library: nil)
        request.watchRoom = launch
        PlaybackCoordinator.shared.play(request)
    }
}
