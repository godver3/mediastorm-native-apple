import XCTest
@testable import StrmrTV

/// Watch Together payloads as the backend writes them (`models/watch_room.go`): captured from a
/// local server (a room with an invited, not yet joined profile, an external invite) plus the
/// account invitation's JSON tags and Go's `null` for empty maps and slices.
final class WatchRoomModelTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static let roomJSON = """
    {"id":"588a2008-60c6-4447-81b1-cc30bfa3113d","creatorProfileId":"default","creatorName":"godver3",
     "title":"Fixture Movie","mediaType":"movie","itemId":"tmdb:movie:603",
     "params":{"mediaType":"movie","title":"Fixture Movie","titleId":"tmdb:movie:603","year":"1999","tmdbId":"603"},
     "status":"lobby","waitingForReady":false,"position":0,"duration":0,"revision":0,"updatedBy":"default",
     "anchorUpdatedAt":"2026-11-23T12:37:26.449048-06:00","createdAt":"2026-11-23T12:37:26.449048-06:00",
     "expiresAt":"2026-11-24T12:37:26.449048-06:00",
     "members":[
      {"profileId":"default","name":"godver3","color":"#EF4444","iconUrl":"default.jpg","clientId":"fixture-client",
       "isCreator":true,"ready":true,"buffering":false,"joined":true,"present":true,
       "joinedAt":"2026-11-23T12:37:26.449048-06:00","lastSeenAt":"2026-11-23T12:37:26.449048-06:00",
       "capabilities":{"nativePlayback":true,"stateSync":true,"protocolVersion":1}},
      {"profileId":"f1d199b3-7c83-4883-bd72-0b5cf8f267ca","name":"Kids","color":"#EAB308","isCreator":false,
       "ready":false,"buffering":false,"joined":false,"present":false,
       "joinedAt":"2026-11-23T12:37:26.449048-06:00","lastSeenAt":"2026-11-22T12:37:26.449048-06:00",
       "capabilities":{"nativePlayback":false,"stateSync":false,"protocolVersion":0}}]}
    """

    func testDecodesARoomFromTheServer() throws {
        let room = try decode(WatchRoom.self, Self.roomJSON)
        XCTAssertEqual(room.id, "588a2008-60c6-4447-81b1-cc30bfa3113d")
        XCTAssertEqual(room.status, .lobby)
        XCTAssertEqual(room.revision, 0)
        XCTAssertTrue(room.isHost("default"))
        XCTAssertFalse(room.isHost("f1d199b3-7c83-4883-bd72-0b5cf8f267ca"))
        XCTAssertEqual(room.members.count, 2)
        XCTAssertEqual(room.joinedMembers.map(\.name), ["godver3"])
        XCTAssertEqual(room.host?.capabilities, .current)
        XCTAssertEqual(room.members[1].initial, "K")
        XCTAssertTrue(room.shouldPause)
        XCTAssertNil(room.endReason)
    }

    func testRoomParamsOpenTheTitle() throws {
        let target = try decode(WatchRoom.self, Self.roomJSON).detailsTarget
        XCTAssertEqual(target.titleID, "tmdb:movie:603")
        XCTAssertEqual(target.name, "Fixture Movie")
        XCTAssertTrue(target.isMovie)
        XCTAssertEqual(target.year, 1999)
        XCTAssertEqual(target.tmdbID, "603")
        XCTAssertNil(target.imdbID)
    }

    func testEndedAndPlayingRoomsAndGoNulls() throws {
        let ended = try decode(WatchRoom.self, """
        {"id":"r1","creatorProfileId":"p","creatorName":"Pat","title":"Show","mediaType":"series",
         "itemId":"tmdb:tv:1","params":null,"status":"ended","waitingForReady":false,"position":12.5,
         "duration":1800,"revision":7,"anchorUpdatedAt":"2026-11-23T12:37:26Z","createdAt":"2026-11-23T12:00:00Z",
         "expiresAt":"2026-11-24T12:00:00Z","endedAt":"2026-11-23T13:00:00.5Z","endReason":"host_ended","members":null}
        """)
        XCTAssertTrue(ended.isEnded)
        XCTAssertEqual(ended.params, [:])
        XCTAssertTrue(ended.members.isEmpty)
        XCTAssertEqual(ended.revision, 7)
        XCTAssertEqual(ended.endReason, "host_ended")
        XCTAssertFalse(ended.detailsTarget.isMovie)
        XCTAssertEqual(ended.detailsTarget.titleID, "tmdb:tv:1")

        let playing = try decode(WatchRoom.self, """
        {"id":"r2","creatorProfileId":"p","creatorName":"Pat","title":"Film","mediaType":"movie","itemId":"x",
         "params":{},"status":"playing","waitingForReady":true,"position":3,"duration":0,"revision":2,
         "anchorUpdatedAt":"2026-11-23T12:37:26Z","createdAt":"2026-11-23T12:00:00Z","expiresAt":"2026-11-24T12:00:00Z",
         "members":[]}
        """)
        XCTAssertEqual(playing.status, .playing)
        XCTAssertTrue(playing.shouldPause, "paused while the room waits for every player")
    }

    func testDecodesInvitationsListAndExternalInvite() throws {
        let rooms = try decode([WatchRoom].self, "[\(Self.roomJSON)]")
        XCTAssertEqual(rooms.first?.creatorName, "godver3")

        let invite = try decode(WatchPartyInvitation.self, """
        {"url":"https://strmr.example/watch-party/vSg-kFb0TPtjJNS3L2hOCl5WQIr3NyBT1Wu-5VVdHgM",
         "landingUrl":"https://strmr.example/watch-party","shortCode":"XUUD-5ECW",
         "expiresAt":"2026-11-24T12:37:26.449048-06:00"}
        """)
        XCTAssertEqual(invite.shortCode, "XUUD-5ECW")
        XCTAssertTrue(invite.url.hasSuffix("5VVdHgM"))
    }

    func testDecodesAccountInvitations() throws {
        let invites = try decode([WatchRoomAccountInvitation].self, """
        [{"id":"i1","roomId":"r1","inviteeUsername":"sam","status":"pending","creatorName":"godver3",
          "title":"Fixture Movie","mediaType":"movie","itemId":"tmdb:movie:603",
          "backdropUrl":"https://image.tmdb.org/t/p/original/b.jpg",
          "createdAt":"2026-11-23T12:37:26.449048-06:00","expiresAt":"2026-11-24T12:37:26.449048-06:00"},
         {"id":"i2","roomId":"r1","acceptedProfileId":"p9","status":"accepted",
          "createdAt":"2026-11-23T12:37:26Z","expiresAt":"2026-11-24T12:37:26Z",
          "respondedAt":"2026-11-23T12:40:00Z"}]
        """)
        XCTAssertEqual(invites.map(\.isPending), [true, false])
        XCTAssertEqual(invites[0].inviteeUsername, "sam")
        XCTAssertEqual(invites[1].acceptedProfileId, "p9")
        XCTAssertEqual(invites[1].creatorName, "")
    }

    func testCreateBodySendsCapabilitiesAndClientID() {
        let body = WatchRoomCreate(title: "T", mediaType: "movie", itemId: "tmdb:movie:1", posterUrl: nil,
                                   backdropUrl: "", params: ["titleId": "tmdb:movie:1"], inviteeProfileIds: ["a"]).json
        XCTAssertEqual(body["clientId"] as? String, Config.clientID)
        let caps = body["capabilities"] as? [String: Any]
        XCTAssertEqual(caps?["nativePlayback"] as? Bool, true)
        XCTAssertEqual(caps?["stateSync"] as? Bool, true)
        XCTAssertEqual(caps?["protocolVersion"] as? Int, 1)
        XCTAssertNil(body["posterUrl"])
        XCTAssertNil(body["backdropUrl"], "an empty URL is left out")
        XCTAssertEqual(body["inviteeProfileIds"] as? [String], ["a"])
    }

    func testDecodesTheRoomsEpisodeAndSendsItOnCreate() throws {
        XCTAssertNil(try decode(WatchRoom.self, Self.roomJSON).episode, "absent on old rooms")
        let room = try decode(WatchRoom.self, """
        {"id":"r","mediaType":"series","episode":{"seasonNumber":2,"episodeNumber":5,"episodeId":"e","title":"Five"}}
        """)
        XCTAssertEqual(room.episode, WatchRoomEpisode(seasonNumber: 2, episodeNumber: 5, episodeId: "e", title: "Five"))
        XCTAssertNil(try decode(WatchRoom.self, #"{"id":"r","episode":{"bogus":1}}"#).episode, "malformed reads as none")
        let create = WatchRoomCreate(title: "T", mediaType: "series", itemId: "i", params: [:], inviteeProfileIds: [],
                                     episode: WatchRoomEpisode(seasonNumber: 1, episodeNumber: 2))
        let body = create.json["episode"] as? [String: Any]
        XCTAssertEqual(body?["seasonNumber"] as? Int, 1)
        XCTAssertEqual(body?["episodeNumber"] as? Int, 2)
        XCTAssertNil(body?["episodeId"])
    }

    func testExternalSourceBindsPerEpisode() {
        let body = APIClient.externalSourceBody(source: "/s", params: ["a": "b"],
                                                episode: WatchRoomEpisode(seasonNumber: 2, episodeNumber: 4))
        XCTAssertEqual(body["source"] as? String, "/s")
        XCTAssertEqual((body["episode"] as? [String: Any])?["episodeNumber"] as? Int, 4)
        XCTAssertNil(APIClient.externalSourceBody(source: "/s", params: [:], episode: nil)["episode"], "movie")
    }
}
