import AetherEngine
import UIKit

/// Watch Together in the VOD player: follows the room once the stream has loaded
/// (`WatchRoomPlaybackSync`), shows who's watching (`WatchTogetherPresenceView`, never
/// focusable), binds the host's stream for web guests, and closes the player when the room
/// ends; the details page it came from then goes back to the lobby.
extension PlayerViewController: WatchRoomSyncedPlayer {
    var syncPosition: Double { lastKnownPosition > 0 ? lastKnownPosition : engine.clock.currentTime }
    var syncDuration: Double { engine.duration > 0 ? engine.duration : lastKnownDuration }
    var syncPaused: Bool { engine.state == .paused }
    var syncBuffering: Bool { engine.isBuffering }

    func applyRoomState(seek: Double?, paused: Bool) {
        Task { [weak self] in
            guard let self, !didFinish else { return }
            if let seek {
                log.info("watch room: seeking to \(Int(seek))s")
                await engine.seek(to: seek)
            }
            if paused, engine.state != .paused {
                engine.pause()
            } else if !paused, engine.state == .paused {
                engine.play()
            }
        }
    }

    func startWatchTogether() {
        guard let launch = request.watchRoom, watchSync == nil else { return }
        let sync = WatchRoomPlaybackSync(launch: launch, playingItem: request.title.titleID,
                                         resumePosition: launch.isHost && launch.position == nil ? request.startPosition : nil,
                                         player: self)
        sync.onRoom = { [weak self] room in self?.showPresence(room) }
        sync.onEnded = { [weak self] in
            guard let self, !didFinish else { return }
            log.notice("watch room ended; leaving the player")
            dismiss(animated: true)
        }
        watchSync = sync
        sync.start()
        bindWatchPartySourceIfHost(launch)
    }

    func stopWatchTogether() {
        guard let watchSync else { return }
        watchSync.stop()
        self.watchSync = nil
        watchPresence.removeFromSuperview()
        WatchTogetherSession.shared.watchRoomPlayerClosed()
    }

    private func showPresence(_ room: WatchRoom?) {
        if watchPresence.superview == nil {
            watchPresence.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(watchPresence)
            // Clear of the clock and the status toast (top right on TV, top centre on the phone)
            // and of the phone's top control bar: top left on TV, lower on the phone's right.
            #if os(tvOS)
            NSLayoutConstraint.activate([
                watchPresence.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
                watchPresence.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 80),
            ])
            #else
            let guide = view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                watchPresence.topAnchor.constraint(equalTo: guide.topAnchor, constant: 110),
                watchPresence.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            ])
            #endif
        }
        view.bringSubviewToFront(watchPresence)
        watchPresence.update(room)
    }

    /// The host shares its resolved stream once, so web guests (who can't resolve on their own)
    /// play the same source. Needs the profile's share-link permission, as on the Expo app.
    private func bindWatchPartySourceIfHost(_ launch: WatchRoomLaunch) {
        guard launch.isHost, !watchSourceBound, !playsDownload,
              AppSession.shared.profile?.allowShareLinks == true else { return }
        watchSourceBound = true
        let params = watchPartyParams
        let path = streamPath
        Task { [weak self] in
            do {
                try await APIClient.shared.bindWatchPartySource(launch.roomID, source: path, params: params)
                self?.log.notice("watch room: stream bound for web guests")
            } catch {
                // A 4xx (another source already bound) won't change on retry.
                if let status = (error as? APIError)?.statusCode, status < 500 { return }
                self?.watchSourceBound = false
                self?.log.error("watch room: binding the stream failed: \(error.localizedDescription)")
            }
        }
    }

    /// The Expo player's allowed external-source params, from this request.
    private var watchPartyParams: [String: String] {
        let t = request.title
        var params = ["mediaType": request.progressMediaType == "episode" ? "series" : "movie",
                      "title": t.name, "titleId": t.titleID, "displayName": request.displayTitle]
        if let v = t.year { params["year"] = String(v) }
        if let v = t.imdbID { params["imdbId"] = v }
        if let v = t.tmdbID { params["tmdbId"] = v }
        if let v = t.tvdbID { params["tvdbId"] = v }
        if let v = t.backdropURL ?? t.posterURL { params["headerImage"] = v }
        if let episode = request.episode {
            params["seriesTitle"] = t.name
            params["seasonNumber"] = String(episode.season)
            params["episodeNumber"] = String(episode.episode)
            if let name = episode.name, !name.isEmpty { params["episodeName"] = name }
        }
        return params
    }
}
