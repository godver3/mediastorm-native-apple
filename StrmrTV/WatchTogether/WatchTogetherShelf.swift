import SwiftUI

/// Home's `watch-together` row: rooms this profile created or was invited to, then pending
/// invitations from other accounts. Each card opens the room's lobby, where an account
/// invitation is accepted or declined. Empty rows are left off Home, as every row is.
enum WatchTogetherShelf {
    /// While Home is on screen and the app is active (the user's call: lighter than Expo's 5 s).
    static let pollInterval: Duration = .seconds(15)

    @MainActor static func cards() async throws -> [HomeCard] {
        let api = APIClient.shared
        async let rooms = api.watchRoomInvitations()
        // Account invitations are a bonus: a failure there keeps the rooms.
        async let invites = try? api.myAccountInvitations()
        let profile = api.profileID
        let roomCards = try await rooms.filter { !$0.isEnded }.map { card($0, profile: profile) }
        let pending = await invites ?? []
        let inviteCards = pending.filter(\.isPending).map(card)
        return roomCards + inviteCards
    }

    private static func card(_ room: WatchRoom, profile: String) -> HomeCard {
        let subtitle: String
        if room.isHost(profile) {
            subtitle = String(localized: "Your room · \(statusText(room))")
        } else if room.member(profile)?.joined == true {
            subtitle = String(localized: "\(room.creatorName)'s room · \(statusText(room))")
        } else {
            subtitle = String(localized: "\(room.creatorName) invited you")
        }
        let present = room.joinedMembers.filter(\.present).map(\.name)
        var card = HomeCard(id: "watch-room-\(room.id)", link: .watchRoom(WatchRoomRoute(roomID: room.id)),
                            title: room.title, subtitle: subtitle,
                            overview: present.isEmpty ? nil : String(localized: "Here now: \(present.joined(separator: ", "))"),
                            backdropURL: room.backdropUrl ?? room.posterUrl)
        card.posterURL = room.posterUrl
        return card
    }

    private static func card(_ invite: WatchRoomAccountInvitation) -> HomeCard {
        var card = HomeCard(id: "watch-invite-\(invite.id)",
                            link: .watchRoom(WatchRoomRoute(roomID: invite.roomId, accountInviteID: invite.id)),
                            title: invite.title, subtitle: String(localized: "\(invite.creatorName) invited your account"),
                            backdropURL: invite.backdropUrl ?? invite.posterUrl)
        card.posterURL = invite.posterUrl
        return card
    }

    private static func statusText(_ room: WatchRoom) -> String {
        switch room.status {
        case .lobby: String(localized: "In the lobby")
        case .playing: String(localized: "Playing")
        case .paused: String(localized: "Paused")
        case .ended: String(localized: "Ended")
        }
    }
}

/// Reloads Home's Watch Together row every 15 s while Home shows (on screen, not `covered` by a
/// pushed page) and the app is active.
struct WatchTogetherShelfPolling: ViewModifier {
    let store: HomeStore
    var covered = false
    @State private var onScreen = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let active = onScreen && !covered && scenePhase == .active
        content
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
            .task(id: active) {
                guard active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: WatchTogetherShelf.pollInterval)
                    guard !Task.isCancelled else { return }
                    await store.reloadWatchTogether()
                }
            }
    }
}
