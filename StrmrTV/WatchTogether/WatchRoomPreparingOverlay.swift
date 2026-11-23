import SwiftUI

/// Over the stream-start loading art while a watch room's playback resolves (the Expo
/// `WatchRoomPreparingOverlay`): the room's title and members, and whether every player is
/// ready. Polls the room every 3 s and heartbeats as buffering, so others see this device
/// preparing; the player's own sync takes over once it is up. Display only.
struct WatchRoomPreparingOverlay: View {
    let launch: WatchRoomLaunch
    @State private var room: WatchRoom?

    #if os(tvOS)
    private let width: CGFloat = 640
    #else
    private let width: CGFloat = 340
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WATCH TOGETHER").font(.caption.weight(.bold)).foregroundStyle(Color(red: 0.58, green: 0.77, blue: 0.99))
            Text(room?.title ?? String(localized: "Watch room")).font(.headline).lineLimit(2)
            HStack(spacing: 10) {
                ProgressView()
                Text(room?.waitingForReady == true ? "Preparing playback on all devices…" : "Playback is getting ready…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let room {
                ForEach(room.members) { WatchRoomMemberRow(member: $0, room: room, preparing: true) }
            }
        }
        .padding(24)
        .frame(width: width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .allowsHitTesting(false)
        .focusable(false)
        .task { await follow() }
    }

    private func follow() async {
        let api = APIClient.shared
        defer {
            let roomID = launch.roomID
            Task { try? await APIClient.shared.heartbeatWatchRoom(roomID, buffering: false) }
        }
        while !Task.isCancelled {
            do {
                let next = try await api.watchRoom(launch.roomID)
                if next.isEnded { return WatchTogetherSession.shared.setActive(roomID: nil, itemID: nil) }
                room = next
                try await api.heartbeatWatchRoom(launch.roomID, buffering: true)
            } catch let error as APIError where error.endsWatchRoom {
                return WatchTogetherSession.shared.setActive(roomID: nil, itemID: nil)
            } catch {
                // Playback resolution carries on whether or not a presence refresh lands.
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
