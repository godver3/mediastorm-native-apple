import XCTest
@testable import StrmrTV

/// The player's room-sync rules (ported from the Expo `useWatchRoomPlaybackSync`) and the
/// per-profile active-room store.
@MainActor
final class WatchRoomSyncTests: XCTestCase {
    private typealias Rules = WatchRoomSyncRules

    func testItemIDsCompareWithoutTheEpisode() {
        XCTAssertEqual(Rules.normalize("tmdb:tv:1399:S01E02"), "tmdb:tv:1399")
        XCTAssertEqual(Rules.normalize("tmdb:tv:1399:s10e12"), "tmdb:tv:1399")
        XCTAssertEqual(Rules.normalize(" tmdb:movie:603 "), "tmdb:movie:603")
        XCTAssertFalse(Rules.isMismatch(roomItem: "tmdb:tv:1399", playing: "tmdb:tv:1399:S02E01"))
        XCTAssertTrue(Rules.isMismatch(roomItem: "tmdb:tv:1399", playing: "tmdb:tv:42"))
        XCTAssertFalse(Rules.isMismatch(roomItem: "", playing: "tmdb:tv:42"), "an unknown item never mismatches")
    }

    private func ep(_ season: Int, _ episode: Int) -> WatchRoomEpisode {
        WatchRoomEpisode(seasonNumber: season, episodeNumber: episode)
    }

    func testHostAnnouncesTheEpisodeItPlays() {
        XCTAssertEqual(Rules.episodeAction(isHost: true, roomEpisode: ep(1, 1), playing: ep(1, 2), itemMismatch: false),
                       .announce(ep(1, 2)), "host advanced (up next)")
        XCTAssertEqual(Rules.episodeAction(isHost: true, roomEpisode: nil, playing: ep(1, 1), itemMismatch: false),
                       .announce(ep(1, 1)), "a room without one learns the host's")
        XCTAssertEqual(Rules.episodeAction(isHost: true, roomEpisode: ep(1, 2), playing: ep(1, 2), itemMismatch: false), .none)
        XCTAssertEqual(Rules.episodeAction(isHost: true, roomEpisode: nil, playing: nil, itemMismatch: false), .none,
                       "movie")
        XCTAssertEqual(Rules.episodeAction(isHost: true, roomEpisode: ep(1, 1), playing: ep(1, 2), itemMismatch: true), .none)
    }

    func testGuestFollowsTheHostsEpisode() {
        XCTAssertEqual(Rules.episodeAction(isHost: false, roomEpisode: ep(1, 3), playing: ep(1, 2), itemMismatch: false),
                       .follow(ep(1, 3)))
        XCTAssertEqual(Rules.episodeAction(isHost: false, roomEpisode: ep(2, 1), playing: nil, itemMismatch: true),
                       .follow(ep(2, 1)), "the room's episode names what to play on another item")
        XCTAssertEqual(Rules.episodeAction(isHost: false, roomEpisode: ep(1, 3), playing: ep(1, 3), itemMismatch: false), .none)
        XCTAssertEqual(
            Rules.episodeAction(isHost: false, roomEpisode: WatchRoomEpisode(seasonNumber: 1, episodeNumber: 3, episodeId: "x"),
                                playing: WatchRoomEpisode(seasonNumber: 1, episodeNumber: 3, title: "T"), itemMismatch: false),
            .none, "IDs and titles don't decide")
    }

    func testRoomWithoutAnEpisodeKeepsLegacyBehaviour() {
        XCTAssertEqual(Rules.episodeAction(isHost: false, roomEpisode: nil, playing: ep(1, 2), itemMismatch: false), .none)
        XCTAssertEqual(Rules.episodeAction(isHost: false, roomEpisode: nil, playing: ep(1, 2), itemMismatch: true), .none)
        XCTAssertTrue(Rules.allowsUpNext(isHost: true))
        XCTAssertFalse(Rules.allowsUpNext(isHost: false))
    }

    func testOnlyTheLobbysHostPlayerSeedsItsResumePoint() {
        let lobby = WatchRoomLaunch(roomID: "r", itemID: "i", isHost: true, position: nil)
        XCTAssertEqual(Rules.hostResumeSeed(launch: lobby, start: 36), 36)
        XCTAssertNil(Rules.hostResumeSeed(launch: lobby.replacement, start: 420), "source switch / Auto Switch / Up Next")
        XCTAssertFalse(lobby.replacement.seedsResume)
        XCTAssertNil(Rules.hostResumeSeed(launch: WatchRoomLaunch(roomID: "r", itemID: "i", isHost: true, position: 420), start: 36))
        XCTAssertNil(Rules.hostResumeSeed(launch: WatchRoomLaunch(roomID: "r", itemID: "i", isHost: false, position: nil), start: 36))
    }

    func testSeeksOnlyBeyondOneAndAHalfSeconds() {
        XCTAssertFalse(Rules.shouldSeek(current: 100, target: 101.4))
        XCTAssertTrue(Rules.shouldSeek(current: 100, target: 101.6))
        XCTAssertTrue(Rules.shouldSeek(current: 100, target: 98))
    }

    func testHostSeedsItsResumePointOnceWhenFarFromTheRoom() {
        XCTAssertTrue(Rules.shouldSeedHostResume(isHost: true, firstSnapshot: true, resume: 600, roomPosition: 0))
        XCTAssertFalse(Rules.shouldSeedHostResume(isHost: false, firstSnapshot: true, resume: 600, roomPosition: 0))
        XCTAssertFalse(Rules.shouldSeedHostResume(isHost: true, firstSnapshot: false, resume: 600, roomPosition: 0))
        XCTAssertFalse(Rules.shouldSeedHostResume(isHost: true, firstSnapshot: true, resume: 0, roomPosition: 30))
        XCTAssertFalse(Rules.shouldSeedHostResume(isHost: true, firstSnapshot: true, resume: 600, roomPosition: 598))
    }

    func testLocalChangesArePausesAndSeeksAgainstTheExtrapolatedPosition() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let playing = Rules.Sample(paused: false, position: 100, at: t0)
        // Playing on as expected: one second later, one second further.
        XCTAssertFalse(Rules.localChange(from: playing, to: .init(paused: false, position: 101, at: t0 + 1)))
        // Small drift is not a seek.
        XCTAssertFalse(Rules.localChange(from: playing, to: .init(paused: false, position: 103, at: t0 + 1)))
        // A seek forward or back.
        XCTAssertTrue(Rules.localChange(from: playing, to: .init(paused: false, position: 130, at: t0 + 1)))
        XCTAssertTrue(Rules.localChange(from: playing, to: .init(paused: false, position: 90, at: t0 + 1)))
        // A pause.
        XCTAssertTrue(Rules.localChange(from: playing, to: .init(paused: true, position: 101, at: t0 + 1)))
        // Paused stays put: no extrapolation.
        let paused = Rules.Sample(paused: true, position: 100, at: t0)
        XCTAssertFalse(Rules.localChange(from: paused, to: .init(paused: true, position: 100, at: t0 + 5)))
        XCTAssertTrue(Rules.localChange(from: paused, to: .init(paused: true, position: 200, at: t0 + 5)))
    }

    func testBufferingNeedsAStuckPlayheadForAWholeInterval() {
        XCTAssertFalse(Rules.sustainedBuffering(raw: true, paused: false, previous: nil, current: 10))
        XCTAssertTrue(Rules.sustainedBuffering(raw: true, paused: false, previous: 10, current: 10.2))
        XCTAssertFalse(Rules.sustainedBuffering(raw: true, paused: false, previous: 10, current: 14))
        XCTAssertFalse(Rules.sustainedBuffering(raw: true, paused: true, previous: 10, current: 10))
        XCTAssertFalse(Rules.sustainedBuffering(raw: false, paused: false, previous: 10, current: 10))
    }

    func testBackgroundPauseIsNeverReported() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var gate = Rules.ReportGate()
        XCTAssertTrue(gate.allowsReporting(at: t0))
        gate.enterBackground()
        XCTAssertFalse(gate.allowsReporting(at: t0 + 60), "nothing is reported while backgrounded")
        gate.becomeActive(at: t0 + 100)
        XCTAssertFalse(gate.allowsReporting(at: t0 + 100.5), "quiet while the room's state is re-applied")
        XCTAssertFalse(gate.allowsReporting(at: t0 + 101.4))
        XCTAssertTrue(gate.allowsReporting(at: t0 + 101.6))
    }

    func testPollingStaysWellInsideThePresenceWindow() {
        XCTAssertEqual(Rules.pollInterval, 2)
        XCTAssertLessThanOrEqual(Rules.heartbeatInterval, 6)
        XCTAssertLessThan(Rules.heartbeatInterval * 2, 15, "two missed heartbeats still keep a member present")
    }

    func testActiveRoomIsKeptPerProfile() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WatchRoomSyncTests"))
        defaults.removePersistentDomain(forName: "WatchRoomSyncTests")
        let session = WatchTogetherSession(defaults: defaults)
        session.setActive(roomID: "room-a", itemID: "tmdb:movie:1", profile: "p1")
        session.setActive(roomID: "room-b", itemID: nil, profile: "p2")
        XCTAssertEqual(session.savedRoom(profile: "p1")?.roomID, "room-a")
        XCTAssertEqual(session.savedRoom(profile: "p1")?.itemID, "tmdb:movie:1")
        XCTAssertEqual(session.savedRoom(profile: "p2")?.roomID, "room-b")
        session.setActive(roomID: nil, itemID: nil, profile: "p1")
        XCTAssertNil(session.savedRoom(profile: "p1"))
        XCTAssertNotNil(session.savedRoom(profile: "p2"))
    }

}
