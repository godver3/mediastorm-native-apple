import Foundation

/// The decisions of the player's room sync (`WatchRoomPlaybackSync`), kept pure for tests. The
/// thresholds are the Expo app's (`useWatchRoomPlaybackSync`).
enum WatchRoomSyncRules {
    /// Applying the room's state seeks only when the player is further off than this.
    static let seekThreshold: Double = 1.5
    /// A local seek is one that lands further than this from where playback should be.
    static let localSeekThreshold: Double = 2.5
    /// After applying the room's state, local changes aren't reported for this long (the
    /// player is still settling into the state it was given).
    static let remoteSettle: TimeInterval = 1.5
    /// The host's resume point replaces the room's start when they differ by more than this.
    static let hostSeedThreshold: Double = 2.5
    /// The playhead must move at least this far between heartbeats to not count as stuck.
    static let advanceThreshold: Double = 0.75

    // Polling (lighter than Expo's 1 s; the user's call): the room every 2 s in the player,
    // a heartbeat every 5 s (well under the server's 15 s presence window), local changes
    // checked every second at no network cost.
    static let pollInterval: TimeInterval = 2
    static let heartbeatInterval: TimeInterval = 5
    static let localTick: Duration = .seconds(1)

    /// A playback sample: paused or not, where, and when it was taken.
    struct Sample: Equatable {
        var paused: Bool
        var position: Double
        var at: Date
    }

    /// Whether local changes may be reported. Backgrounding pauses playback by itself (iOS), and
    /// that pause is not the viewer's: nothing is reported while in the background nor for
    /// `remoteSettle` after coming back, by which time the room's state has been pulled and applied.
    struct ReportGate: Equatable {
        private(set) var backgrounded = false
        private(set) var quietUntil = Date.distantPast

        mutating func enterBackground() { backgrounded = true }
        mutating func becomeActive(at now: Date) {
            backgrounded = false
            quietUntil = now.addingTimeInterval(remoteSettle)
        }
        func allowsReporting(at now: Date) -> Bool { !backgrounded && now >= quietUntil }
    }

    /// The room's item without an episode suffix (`tmdb:tv:1:S01E02` → `tmdb:tv:1`).
    static func normalize(_ itemID: String?) -> String {
        let value = (itemID ?? "").trimmingCharacters(in: .whitespaces)
        guard let range = value.range(of: #":S\d+E\d+$"#, options: [.regularExpression, .caseInsensitive]) else {
            return value
        }
        return String(value[..<range.lowerBound])
    }

    /// The room is for something else than what plays (an episode change still in progress).
    static func isMismatch(roomItem: String, playing: String?) -> Bool {
        let expected = normalize(roomItem), current = normalize(playing)
        return !expected.isEmpty && !current.isEmpty && expected != current
    }

    /// What a player does about the room's episode.
    enum EpisodeAction: Equatable {
        /// Nothing: same episode, a movie, or a room without one (legacy: everyone plays their own).
        case none
        /// Host: the room doesn't have the episode this player plays yet; post it.
        case announce(WatchRoomEpisode)
        /// Guest: the host plays another episode (or this player is on another item); switch to it.
        case follow(WatchRoomEpisode)
    }

    /// The host leads the room's episode; guests follow it. A guest follows even when the item
    /// mismatches, since the room's episode names what to play.
    static func episodeAction(isHost: Bool, roomEpisode: WatchRoomEpisode?, playing: WatchRoomEpisode?,
                              itemMismatch: Bool) -> EpisodeAction {
        if isHost {
            guard !itemMismatch, let playing, !playing.same(roomEpisode) else { return .none }
            return .announce(playing)
        }
        guard let roomEpisode else { return .none }
        return itemMismatch || !roomEpisode.same(playing) ? .follow(roomEpisode) : .none
    }

    /// Up Next in a room: only the host advances (the guests follow the room's episode).
    static func allowsUpNext(isHost: Bool) -> Bool { isHost }

    static func shouldSeek(current: Double, target: Double) -> Bool {
        abs(current - target) > seekThreshold
    }

    /// The host opened the title with a resume point the room doesn't have yet.
    static func shouldSeedHostResume(isHost: Bool, firstSnapshot: Bool, resume: Double, roomPosition: Double) -> Bool {
        isHost && firstSnapshot && resume > 0 && abs(roomPosition - resume) > hostSeedThreshold
    }

    /// Whether playback changed locally since `previous`: paused or resumed, or a position
    /// more than 2.5 s from where it should be by now.
    static func localChange(from previous: Sample, to now: Sample) -> Bool {
        let expected = previous.paused ? previous.position : previous.position + now.at.timeIntervalSince(previous.at)
        return now.paused != previous.paused || abs(now.position - expected) > localSeekThreshold
    }

    /// Buffering as the heartbeat reports it: the player says so, it isn't paused, and the
    /// playhead didn't move through a whole heartbeat interval (decoders flag short stalls while
    /// frames still advance).
    static func sustainedBuffering(raw: Bool, paused: Bool, previous: Double?, current: Double) -> Bool {
        guard raw, !paused, let previous else { return false }
        return current - previous < advanceThreshold
    }
}
