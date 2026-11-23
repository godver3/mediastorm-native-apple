import Foundation

/// Watch Together. Room calls are profile-scoped (`/api/users/{profileId}/watch-rooms…`); the
/// account invitations list and its decline are account-scoped. Calls the player and the polls
/// make in the background never prompt for a PIN (`promptOnLock: false`).
extension APIClient {
    private func roomPath(_ roomID: String, _ suffix: String = "") -> String {
        "\(profilePath)/watch-rooms/\(Self.segment(roomID))\(suffix)"
    }

    private var joinBody: [String: Any] {
        ["clientId": Config.clientID, "capabilities": WatchRoomCapabilities.current.json]
    }

    func createWatchRoom(_ create: WatchRoomCreate) async throws -> WatchRoom {
        try await send("POST", "\(profilePath)/watch-rooms", jsonObject: create.json)
    }

    func watchRoom(_ roomID: String) async throws -> WatchRoom {
        try await send("GET", roomPath(roomID), promptOnLock: false, timeout: 20)
    }

    /// Idempotent: also refreshes this device's client ID and capabilities on the member.
    func joinWatchRoom(_ roomID: String) async throws -> WatchRoom {
        try await send("POST", roomPath(roomID, "/join"), jsonObject: joinBody)
    }

    func setWatchRoomReady(_ roomID: String, ready: Bool) async throws -> WatchRoom {
        try await send("POST", roomPath(roomID, "/ready"), jsonObject: ["ready": ready], promptOnLock: false)
    }

    /// Moves the room's playback. A 409 means another member moved it first (stale
    /// `expectedRevision`); the next poll brings the new state.
    func updateWatchRoomState(_ roomID: String, playing: Bool, position: Double, duration: Double? = nil,
                              expectedRevision: Int64? = nil) async throws -> WatchRoom {
        var body: [String: Any] = ["status": playing ? "playing" : "paused", "position": max(0, position)]
        if let duration, duration > 0 { body["duration"] = duration }
        if let expectedRevision { body["expectedRevision"] = expectedRevision }
        return try await send("POST", roomPath(roomID, "/state"), jsonObject: body, promptOnLock: false, timeout: 20)
    }

    func heartbeatWatchRoom(_ roomID: String, buffering: Bool = false) async throws {
        try await sendRaw("POST", roomPath(roomID, "/heartbeat"),
                          jsonObject: ["clientId": Config.clientID, "buffering": buffering],
                          promptOnLock: false, timeout: 20)
    }

    func leaveWatchRoom(_ roomID: String) async throws {
        try await sendRaw("POST", roomPath(roomID, "/leave"))
    }

    func endWatchRoom(_ roomID: String) async throws {
        try await sendRaw("POST", roomPath(roomID, "/end"))
    }

    /// Rooms this profile created or was invited to that haven't ended (Home's shelf).
    func watchRoomInvitations() async throws -> [WatchRoom] {
        try await send("GET", "\(profilePath)/watch-rooms/invitations", promptOnLock: false, timeout: 20)
    }

    // MARK: Account invitations

    func inviteAccount(_ username: String, to roomID: String) async throws -> WatchRoomAccountInvitation {
        try await send("POST", roomPath(roomID, "/account-invites"), jsonObject: ["username": username])
    }

    /// The host's invitations for one room.
    func roomAccountInvitations(_ roomID: String) async throws -> [WatchRoomAccountInvitation] {
        try await send("GET", roomPath(roomID, "/account-invites"), promptOnLock: false, timeout: 20)
    }

    func revokeAccountInvitation(_ inviteID: String, room roomID: String) async throws {
        try await sendRaw("DELETE", roomPath(roomID, "/account-invites/\(Self.segment(inviteID))"))
    }

    /// Invitations other accounts sent this account (not profile-scoped).
    func myAccountInvitations() async throws -> [WatchRoomAccountInvitation] {
        try await send("GET", "/api/watch-room-account-invitations", promptOnLock: false, timeout: 20)
    }

    /// Accepts into this profile; returns the room, which the caller then joins.
    func acceptAccountInvitation(_ inviteID: String) async throws -> WatchRoom {
        try await send("POST", "\(profilePath)/watch-room-account-invitations/\(Self.segment(inviteID))/accept")
    }

    func declineAccountInvitation(_ inviteID: String) async throws {
        try await sendRaw("POST", "/api/watch-room-account-invitations/\(Self.segment(inviteID))/decline")
    }

    // MARK: External guests

    func createExternalInvitation(_ roomID: String) async throws -> WatchPartyInvitation {
        try await send("POST", roomPath(roomID, "/external-invite"))
    }

    func revokeExternalInvitation(_ roomID: String) async throws {
        try await sendRaw("DELETE", roomPath(roomID, "/external-invite"))
    }

    /// The host's resolved stream, so web guests can play the same source.
    func bindWatchPartySource(_ roomID: String, source: String, params: [String: String]) async throws {
        try await sendRaw("POST", roomPath(roomID, "/external-source"),
                          jsonObject: ["source": source, "params": params], promptOnLock: false, timeout: 60)
    }

    /// A link or QR value from the server: absolute as sent, else against the server.
    func publicURL(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        return url(value).absoluteString
    }
}

extension APIError {
    /// The room is gone for good (410): stop following it.
    var endsWatchRoom: Bool { statusCode == 410 }
    /// The saved room can't be restored (gone, not a member, or unknown).
    var dropsSavedWatchRoom: Bool { [403, 404, 410].contains(statusCode ?? 0) }
}
