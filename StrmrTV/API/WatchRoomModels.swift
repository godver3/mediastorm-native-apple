import Foundation

// Watch Together (`/api/users/{id}/watch-rooms…`), from the backend's `models/watch_room.go`.
// Timestamps stay strings: Go writes them with nanoseconds and a zone offset, and the app only
// compares or shows them.

/// What a client tells the room it can do; a member without `stateSync` can't follow playback.
struct WatchRoomCapabilities: Codable, Hashable, Sendable {
    var nativePlayback: Bool
    var stateSync: Bool
    var protocolVersion: Int

    /// This app: plays natively and follows the room's state, protocol 1 (polling).
    static let current = WatchRoomCapabilities(nativePlayback: true, stateSync: true, protocolVersion: 1)

    var json: [String: Any] {
        ["nativePlayback": nativePlayback, "stateSync": stateSync, "protocolVersion": protocolVersion]
    }
}

/// The episode a series room plays: the host's, which guests follow. Absent for movies and
/// rooms from older servers or hosts (each member then plays their own next-up episode).
struct WatchRoomEpisode: Codable, Hashable, Sendable {
    var seasonNumber: Int
    var episodeNumber: Int
    var episodeId: String?
    var title: String?

    /// Same episode: season and number decide (IDs and titles are informational).
    func same(_ other: WatchRoomEpisode?) -> Bool {
        other.map { $0.seasonNumber == seasonNumber && $0.episodeNumber == episodeNumber } ?? false
    }

    var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }

    var json: [String: Any] {
        var body: [String: Any] = ["seasonNumber": seasonNumber, "episodeNumber": episodeNumber]
        if let episodeId, !episodeId.isEmpty { body["episodeId"] = episodeId }
        if let title, !title.isEmpty { body["title"] = title }
        return body
    }
}

struct WatchRoomMember: Decodable, Hashable, Identifiable, Sendable {
    let profileId: String
    let name: String
    let isGuest: Bool
    let color: String?
    let iconUrl: String?
    let clientId: String?
    let isCreator: Bool
    let ready: Bool
    let buffering: Bool
    /// Accepted the invitation (invited members are listed before they join).
    let joined: Bool
    /// Seen within the server's presence window (15 s).
    let present: Bool
    let joinedAt: String?
    let lastSeenAt: String?
    let capabilities: WatchRoomCapabilities?

    var id: String { profileId }
    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    enum CodingKeys: String, CodingKey {
        case profileId, name, isGuest, color, iconUrl, clientId, isCreator, ready, buffering, joined, present
        case joinedAt, lastSeenAt, capabilities
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profileId = try c.decode(String.self, forKey: .profileId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isGuest = try c.decodeIfPresent(Bool.self, forKey: .isGuest) ?? false
        color = try c.decodeIfPresent(String.self, forKey: .color)
        iconUrl = try c.decodeIfPresent(String.self, forKey: .iconUrl)
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)
        isCreator = try c.decodeIfPresent(Bool.self, forKey: .isCreator) ?? false
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        buffering = try c.decodeIfPresent(Bool.self, forKey: .buffering) ?? false
        joined = try c.decodeIfPresent(Bool.self, forKey: .joined) ?? false
        present = try c.decodeIfPresent(Bool.self, forKey: .present) ?? false
        joinedAt = try c.decodeIfPresent(String.self, forKey: .joinedAt)
        lastSeenAt = try c.decodeIfPresent(String.self, forKey: .lastSeenAt)
        capabilities = try c.decodeIfPresent(WatchRoomCapabilities.self, forKey: .capabilities)
    }
}

struct WatchRoom: Decodable, Hashable, Identifiable, Sendable {
    enum Status: String, Sendable {
        case lobby, playing, paused, ended
    }

    let id: String
    let creatorProfileId: String
    let creatorName: String
    let title: String
    let mediaType: String
    let itemId: String
    let posterUrl: String?
    let backdropUrl: String?
    /// The details-route params the room was created with, used to reopen the title.
    let params: [String: String]
    let statusRaw: String
    let waitingForReady: Bool
    let position: Double
    let duration: Double
    let revision: Int64
    let updatedBy: String?
    let anchorUpdatedAt: String?
    let createdAt: String?
    let expiresAt: String?
    let endedAt: String?
    /// `host_ended`, `host_disconnected`, `all_left` or `expired`.
    let endReason: String?
    let members: [WatchRoomMember]
    /// The host's episode (series rooms from servers that track it).
    let episode: WatchRoomEpisode?

    /// Unknown statuses read as `lobby`, so a newer server can't stop the app following one.
    var status: Status { Status(rawValue: statusRaw) ?? .lobby }
    var isEnded: Bool { status == .ended }
    var isMovie: Bool { mediaType == "movie" }
    /// Playback should be paused: still waiting for every player, or not playing.
    var shouldPause: Bool { waitingForReady || status != .playing }
    var host: WatchRoomMember? { members.first(where: \.isCreator) }
    var joinedMembers: [WatchRoomMember] { members.filter(\.joined) }

    func member(_ profileID: String) -> WatchRoomMember? { members.first { $0.profileId == profileID } }
    func isHost(_ profileID: String) -> Bool { creatorProfileId == profileID }

    var endReasonText: String {
        switch endReason {
        case "host_ended": String(localized: "The host ended this watch room.")
        case "host_disconnected": String(localized: "The host disconnected.")
        case "all_left": String(localized: "Everyone left this watch room.")
        case "expired": String(localized: "This watch room expired.")
        default: String(localized: "This watch room has ended.")
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, creatorProfileId, creatorName, title, mediaType, itemId, posterUrl, backdropUrl, params
        case statusRaw = "status"
        case waitingForReady, position, duration, revision, updatedBy, anchorUpdatedAt, createdAt, expiresAt
        case endedAt, endReason, members, episode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        creatorProfileId = try c.decodeIfPresent(String.self, forKey: .creatorProfileId) ?? ""
        creatorName = try c.decodeIfPresent(String.self, forKey: .creatorName) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? "movie"
        itemId = try c.decodeIfPresent(String.self, forKey: .itemId) ?? ""
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl)
        backdropUrl = try c.decodeIfPresent(String.self, forKey: .backdropUrl)
        // Go writes a nil map as `null`.
        params = try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        statusRaw = try c.decodeIfPresent(String.self, forKey: .statusRaw) ?? "lobby"
        waitingForReady = try c.decodeIfPresent(Bool.self, forKey: .waitingForReady) ?? false
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        revision = try c.decodeIfPresent(Int64.self, forKey: .revision) ?? 0
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy)
        anchorUpdatedAt = try c.decodeIfPresent(String.self, forKey: .anchorUpdatedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt)
        endReason = try c.decodeIfPresent(String.self, forKey: .endReason)
        members = try c.decodeIfPresent([WatchRoomMember].self, forKey: .members) ?? []
        // A malformed episode reads as none (legacy behaviour) rather than failing the room.
        episode = try? c.decodeIfPresent(WatchRoomEpisode.self, forKey: .episode)
    }
}

/// An invitation sent to another server account (`/watch-room-account-invitations`, and a
/// room's own `account-invites` list for the host).
struct WatchRoomAccountInvitation: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let roomId: String
    /// `pending`, `accepted`, `declined` or `revoked`.
    let status: String
    let inviteeUsername: String?
    let acceptedProfileId: String?
    let creatorName: String
    let title: String
    let mediaType: String
    let itemId: String
    let posterUrl: String?
    let backdropUrl: String?
    let createdAt: String?
    let expiresAt: String?

    var isPending: Bool { status == "pending" }

    enum CodingKeys: String, CodingKey {
        case id, roomId, status, inviteeUsername, acceptedProfileId, creatorName, title, mediaType, itemId
        case posterUrl, backdropUrl, createdAt, expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        roomId = try c.decodeIfPresent(String.self, forKey: .roomId) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        inviteeUsername = try c.decodeIfPresent(String.self, forKey: .inviteeUsername)
        acceptedProfileId = try c.decodeIfPresent(String.self, forKey: .acceptedProfileId)
        creatorName = try c.decodeIfPresent(String.self, forKey: .creatorName) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? "movie"
        itemId = try c.decodeIfPresent(String.self, forKey: .itemId) ?? ""
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl)
        backdropUrl = try c.decodeIfPresent(String.self, forKey: .backdropUrl)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}

/// The external guest link (`POST …/external-invite`): guests open it in a browser and watch in
/// the web player.
struct WatchPartyInvitation: Decodable, Hashable, Sendable {
    let url: String
    let landingUrl: String
    let shortCode: String
    let expiresAt: String?
}

/// What creating a room sends (`POST /users/{id}/watch-rooms`).
struct WatchRoomCreate {
    var title: String
    var mediaType: String
    var itemId: String
    var posterUrl: String?
    var backdropUrl: String?
    var params: [String: String]
    var inviteeProfileIds: [String]
    /// The episode the host starts with, when the details page has one.
    var episode: WatchRoomEpisode? = nil

    var json: [String: Any] {
        var body: [String: Any] = [
            "title": title, "mediaType": mediaType, "itemId": itemId, "params": params,
            "inviteeProfileIds": inviteeProfileIds, "clientId": Config.clientID,
            "capabilities": WatchRoomCapabilities.current.json,
        ]
        if let posterUrl, !posterUrl.isEmpty { body["posterUrl"] = posterUrl }
        if let backdropUrl, !backdropUrl.isEmpty { body["backdropUrl"] = backdropUrl }
        if let episode { body["episode"] = episode.json }
        return body
    }
}
