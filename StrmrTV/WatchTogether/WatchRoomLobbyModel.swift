import Foundation
import UIKit

/// Opens a watch room's lobby: a room this profile is in or was invited to, or an account
/// invitation still to accept (`accountInviteID`).
struct WatchRoomRoute: Hashable {
    let roomID: String
    var accountInviteID: String?
    /// The host asked for an external guest link when creating the room.
    var createExternalInvite = false
}

/// A watch room's lobby, shared by the TV and phone screens (the Expo `watch-room` screen):
/// joins the room and polls it every 3 s with a heartbeat while the lobby is on screen, the
/// host's account invitations alongside (about every 5 s), ready / start / leave / end, the
/// external guest link, and starting the player itself once playback starts
/// (`WatchRoomPlaybackStarter`); closing the player lands back here.
@MainActor
final class WatchRoomLobbyModel: ObservableObject {
    private let log = AppLog(category: "watch-together")
    private let api = APIClient.shared
    let route: WatchRoomRoute

    @Published private(set) var room: WatchRoom?
    /// An account invitation waiting for Accept or Decline (nil once accepted, or for rooms).
    @Published private(set) var accountInvitation: WatchRoomAccountInvitation?
    @Published private(set) var pendingAccountInvites: [WatchRoomAccountInvitation] = []
    @Published private(set) var externalInvitation: WatchPartyInvitation?
    @Published var error: String?
    @Published private(set) var busy = false
    /// The room is over (ended, or gone).
    @Published private(set) var ended = false
    /// This lobby already opened the player once: it offers Rejoin Playback instead of reopening.
    @Published private(set) var opened = false
    /// Decline (or a host's Back) finished: the screen closes.
    @Published private(set) var closed = false

    private var roomID: String
    private var joined = false
    private var awaitingAccept: Bool
    private var poll: Task<Void, Never>?
    private var lastInviteRefresh = Date.distantPast
    private var externalAttempted: Bool

    static let pollInterval: Duration = .seconds(3)
    static let inviteRefresh: TimeInterval = 5

    init(route: WatchRoomRoute) {
        self.route = route
        roomID = route.roomID
        awaitingAccept = route.accountInviteID != nil
        externalAttempted = !route.createExternalInvite
    }

    var profileID: String { api.profileID }
    var isHost: Bool { room?.isHost(profileID) == true }
    var me: WatchRoomMember? { room?.member(profileID) }
    var title: String { room?.title ?? accountInvitation?.title ?? String(localized: "Watch Together") }
    var backdropURL: String? { room?.backdropUrl ?? accountInvitation?.backdropUrl }
    /// Playback has started: the lobby offers to (re)join it.
    var isPlaying: Bool { room.map { $0.status == .playing || $0.status == .paused } ?? false }
    /// The host's episode while playback runs (Rejoin Playback starts it; the lobby never reopens
    /// the player by itself when the host moves on).
    var hostEpisodeText: String? {
        guard isPlaying, let episode = room?.episode else { return nil }
        return String(localized: "Host is on \(episode.code)")
    }

    // MARK: Polling

    /// Polls while the lobby is on screen (from `onAppear`); `stop` from `onDisappear`.
    func start() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            if self?.awaitingAccept == true { await self?.loadAccountInvitation() }
            while !Task.isCancelled {
                guard let self else { return }
                if !self.awaitingAccept, !self.ended, UIApplication.shared.applicationState == .active {
                    await self.refresh()
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
    }

    private func refresh() async {
        do {
            var next = try await api.watchRoom(roomID)
            if next.isEnded {
                finish(next)
                return
            }
            if !joined {
                // Idempotent; refreshes this device's client ID and capabilities too.
                next = try await api.joinWatchRoom(roomID)
                joined = true
            }
            room = next
            error = nil
            WatchTogetherSession.shared.setActive(next)
            try await api.heartbeatWatchRoom(roomID)
            if next.isHost(profileID) { await refreshHostExtras() }
            openIfPlaying(next)
        } catch let failure as APIError where failure.endsWatchRoom {
            finish(nil)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshHostExtras() async {
        if !externalAttempted {
            externalAttempted = true
            await createExternalInvitation()
        }
        guard Date.now.timeIntervalSince(lastInviteRefresh) >= Self.inviteRefresh - 0.5 else { return }
        lastInviteRefresh = .now
        if let invites = try? await api.roomAccountInvitations(roomID) {
            pendingAccountInvites = invites.filter(\.isPending)
        }
    }

    private func finish(_ room: WatchRoom?) {
        if let room { self.room = room }
        ended = true
        WatchTogetherSession.shared.setActive(roomID: nil, itemID: nil)
    }

    // MARK: Account invitation

    private func loadAccountInvitation() async {
        guard let id = route.accountInviteID else { return }
        do {
            accountInvitation = try await api.myAccountInvitations().first { $0.id == id }
            if accountInvitation == nil { error = String(localized: "This invitation is no longer available.") }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func acceptInvitation() async {
        guard let id = route.accountInviteID else { return }
        await run {
            let accepted = try await self.api.acceptAccountInvitation(id)
            self.roomID = accepted.id
            self.room = try await self.api.joinWatchRoom(accepted.id)
            self.joined = true
            self.awaitingAccept = false
            self.accountInvitation = nil
            WatchTogetherSession.shared.setActive(self.room)
        }
    }

    func declineInvitation() async {
        guard let id = route.accountInviteID else { return }
        await run {
            try await self.api.declineAccountInvitation(id)
            self.closed = true
        }
    }

    // MARK: Actions

    func toggleReady() async {
        guard let me else { return }
        await run { self.room = try await self.api.setWatchRoomReady(self.roomID, ready: !me.ready) }
    }

    /// Host: starts playback for everyone; the poll then opens the title here too.
    func startPlayback() async {
        guard let room else { return }
        await run {
            let started = try await self.api.updateWatchRoomState(self.roomID, playing: true, position: room.position)
            self.room = started
            self.openIfPlaying(started)
        }
    }

    /// Host: ends the room for everyone. Others leave it.
    func exit() async {
        guard let room else { return }
        await run {
            if room.isHost(self.profileID) {
                try await self.api.endWatchRoom(self.roomID)
            } else {
                try await self.api.leaveWatchRoom(self.roomID)
            }
            self.stop()
            WatchTogetherSession.shared.setActive(roomID: nil, itemID: nil)
            self.closed = true
        }
    }

    func inviteAccount(_ username: String) async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await run {
            let invite = try await self.api.inviteAccount(name, to: self.roomID)
            self.pendingAccountInvites.removeAll { $0.id == invite.id }
            self.pendingAccountInvites.append(invite)
        }
    }

    func revoke(_ invite: WatchRoomAccountInvitation) async {
        await run {
            try await self.api.revokeAccountInvitation(invite.id, room: self.roomID)
            self.pendingAccountInvites.removeAll { $0.id == invite.id }
        }
    }

    func createExternalInvitation() async {
        await run { self.externalInvitation = try await self.api.createExternalInvitation(self.roomID) }
    }

    func revokeExternalInvitation() async {
        await run {
            try await self.api.revokeExternalInvitation(self.roomID)
            self.externalInvitation = nil
        }
    }

    /// Plays the title at the room's position (Join / Rejoin Playback, or the room starting).
    func openTitle() {
        guard let room, PlaybackCoordinator.shared.resolving == nil else { return }
        opened = true
        log.notice("playing \(room.itemId) for room \(room.id) at \(Int(room.position))s")
        Task {
            do {
                try await WatchRoomPlaybackStarter.play(room, profileID: profileID)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func openIfPlaying(_ room: WatchRoom) {
        guard room.status == .playing, !opened else { return }
        openTitle()
    }

    private func run(_ action: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await action()
            error = nil
        } catch let failure as APIError where failure.endsWatchRoom {
            finish(nil)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
