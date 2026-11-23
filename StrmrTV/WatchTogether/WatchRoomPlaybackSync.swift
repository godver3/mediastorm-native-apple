import Foundation
import UIKit

/// What the room sync needs from a player.
@MainActor
protocol WatchRoomSyncedPlayer: AnyObject {
    var syncPosition: Double { get }
    var syncDuration: Double { get }
    var syncPaused: Bool { get }
    var syncBuffering: Bool { get }
    /// Seeks (when `seek` is set) and pauses or plays, to the room's state.
    func applyRoomState(seek: Double?, paused: Bool)
}

/// Keeps a player in step with its watch room (the Expo app's `useWatchRoomPlaybackSync`, with
/// lighter polling): polls the room every 2 s and applies new revisions, reports this player's
/// own pauses and seeks at once (checked every second), heartbeats every 5 s, reports ready
/// while the room waits for every player, and stops when the room ends. Nothing runs while
/// the app is in the background. Live TV never starts one.
@MainActor
final class WatchRoomPlaybackSync {
    private typealias Rules = WatchRoomSyncRules
    private let log = AppLog(category: "watch-together")
    let launch: WatchRoomLaunch
    /// What plays, for the item-mismatch check (the title's ID, without an episode).
    private let playingItem: String
    private let resumePosition: Double
    private weak var player: WatchRoomSyncedPlayer?
    private let api = APIClient.shared

    /// The room as last seen (nil while it is for another item): the presence overlay.
    var onRoom: ((WatchRoom?) -> Void)?
    /// The room ended (or is gone): the player returns to the lobby.
    var onEnded: (() -> Void)?

    private var loop: Task<Void, Never>?
    private var lastRevision: Int64 = -1
    private var applyingRemoteUntil = Date.distantPast
    private var local: Rules.Sample?
    private var lastPoll = Date.distantPast
    private var lastHeartbeat = Date.distantPast
    private var heartbeatPosition: Double?
    private var pollInFlight = false
    private var readyReported = false
    private var waitingForReady = false
    private var presenceSignature = ""
    private var ended = false
    private var gate = Rules.ReportGate()
    /// Back from the background: the next poll re-applies the room's state whatever its revision.
    private var reapply = false
    private var observers: [NSObjectProtocol] = []

    init(launch: WatchRoomLaunch, playingItem: String, resumePosition: Double?, player: WatchRoomSyncedPlayer) {
        self.launch = launch
        self.playingItem = playingItem
        self.resumePosition = max(0, resumePosition ?? 0)
        self.player = player
    }

    /// Starts once the player has loaded.
    func start() {
        guard loop == nil, !ended else { return }
        log.notice("following room \(launch.roomID) (host: \(launch.isHost))")
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enteredBackground() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            },
        ]
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Rules.localTick)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if waitingForReady, readyReported, !ended {
            let room = launch.roomID
            Task { try? await APIClient.shared.setWatchRoomReady(room, ready: false) }
        }
        readyReported = false
        waitingForReady = false
    }

    func enteredBackground() {
        gate.enterBackground()
        local = nil
    }

    /// Pull the room now and re-apply it; local reporting stays quiet meanwhile.
    func becameActive() {
        guard gate.backgrounded else { return }
        gate.becomeActive(at: .now)
        local = nil
        reapply = true
        lastPoll = .distantPast
    }

    private var isActive: Bool { UIApplication.shared.applicationState == .active }

    private func tick() async {
        guard !ended, isActive, let player else { return }
        let now = Date.now
        if !pollInFlight, now.timeIntervalSince(lastPoll) >= Rules.pollInterval {
            lastPoll = now
            pollInFlight = true
            Task { [weak self] in
                await self?.poll()
                self?.pollInFlight = false
            }
        }
        if now.timeIntervalSince(lastHeartbeat) >= Rules.heartbeatInterval {
            lastHeartbeat = now
            heartbeat(player)
        }
        detectLocalChange(player, now: now)
    }

    // MARK: Room → player

    private func poll() async {
        do {
            var room = try await api.watchRoom(launch.roomID)
            guard !ended, let player else { return }
            if room.isEnded { return end(room) }
            if room.waitingForReady, !readyReported {
                room = try await api.setWatchRoomReady(launch.roomID, ready: true)
                readyReported = true
                log.notice("player ready reported for room \(launch.roomID)")
            }
            waitingForReady = room.waitingForReady
            if Rules.isMismatch(roomItem: room.itemId, playing: playingItem) {
                publish(nil)
                return
            }
            let first = lastRevision < 0
            if Rules.shouldSeedHostResume(isHost: launch.isHost, firstSnapshot: first, resume: resumePosition,
                                          roomPosition: room.position) {
                log.notice("seeding host resume \(Int(self.resumePosition))s over room position \(Int(room.position))s")
                room = try await api.updateWatchRoomState(launch.roomID, playing: room.status != .paused,
                                                          position: resumePosition,
                                                          duration: max(room.duration, player.syncDuration),
                                                          expectedRevision: room.revision)
            }
            publish(room)
            guard room.revision != lastRevision || reapply else { return }
            reapply = false
            lastRevision = room.revision
            applyingRemoteUntil = Date.now.addingTimeInterval(Rules.remoteSettle)
            let seek = Rules.shouldSeek(current: player.syncPosition, target: room.position) ? room.position : nil
            log.info("applying revision \(room.revision): \(room.statusRaw) at \(Int(room.position))s"
                + (seek == nil ? "" : " (seek)") + (room.waitingForReady ? ", waiting for ready" : ""))
            player.applyRoomState(seek: seek, paused: room.shouldPause)
            local = Rules.Sample(paused: room.shouldPause, position: room.position, at: .now)
        } catch let error as APIError where error.endsWatchRoom {
            end(nil)
        } catch let error as APIError where error.statusCode == 409 {
            // The host's resume seed lost to another member's change: the next poll has it.
        } catch is CancellationError {
        } catch {
            log.error("room poll failed: \(error.localizedDescription)")
        }
    }

    /// Publishes the room to the overlay when its members' state changed.
    private func publish(_ room: WatchRoom?) {
        let signature = room.map { room in
            room.id + room.members.map { m in
                "\(m.profileId):\(m.name):\(m.color ?? ""):\(m.joined):\(m.present):\(m.ready):\(m.buffering)"
            }.joined(separator: "|") + "\(room.waitingForReady)"
        } ?? ""
        guard signature != presenceSignature else { return }
        presenceSignature = signature
        onRoom?(room)
    }

    // MARK: Player → room

    private func detectLocalChange(_ player: WatchRoomSyncedPlayer, now: Date) {
        guard now >= applyingRemoteUntil, gate.allowsReporting(at: now) else {
            if !gate.allowsReporting(at: now) { local = nil }
            return
        }
        let sample = Rules.Sample(paused: player.syncPaused, position: max(0, player.syncPosition), at: now)
        defer { local = sample }
        guard let previous = local, Rules.localChange(from: previous, to: sample) else { return }
        // While the room waits for every player, its pause is the room's, not a viewer's.
        if waitingForReady, sample.paused { return }
        let expected = lastRevision >= 0 ? lastRevision : nil
        log.info("local change: \(sample.paused ? "paused" : "playing") at \(Int(sample.position))s")
        let room = launch.roomID, duration = player.syncDuration
        Task { [weak self] in
            do {
                let updated = try await APIClient.shared.updateWatchRoomState(
                    room, playing: !sample.paused, position: sample.position, duration: duration,
                    expectedRevision: expected)
                self?.lastRevision = updated.revision
            } catch let error as APIError where error.statusCode == 409 {
                // Stale revision: another member moved first; the next poll brings their state.
            } catch let error as APIError where error.endsWatchRoom {
                self?.end(nil)
            } catch {
                self?.log.error("state update failed: \(error.localizedDescription)")
            }
        }
    }

    private func heartbeat(_ player: WatchRoomSyncedPlayer) {
        let position = max(0, player.syncPosition)
        let buffering = Rules.sustainedBuffering(raw: player.syncBuffering, paused: player.syncPaused,
                                                 previous: heartbeatPosition, current: position)
        heartbeatPosition = position
        let room = launch.roomID
        Task { [weak self] in
            do {
                try await APIClient.shared.heartbeatWatchRoom(room, buffering: buffering)
            } catch let error as APIError where error.endsWatchRoom {
                self?.end(nil)
            } catch {
                self?.log.error("heartbeat failed: \(error.localizedDescription)")
            }
        }
    }

    private func end(_ room: WatchRoom?) {
        guard !ended else { return }
        ended = true
        log.notice("room \(launch.roomID) ended (\(room?.endReason ?? "gone"))")
        loop?.cancel()
        loop = nil
        WatchTogetherSession.shared.setActive(roomID: nil, itemID: nil)
        onEnded?()
    }
}
