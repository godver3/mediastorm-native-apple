import SwiftUI

/// One member in the lobby or the preparing card: avatar initial on the profile colour, name
/// (Host), and joined / present / ready / buffering state.
struct WatchRoomMemberRow: View {
    let member: WatchRoomMember
    let room: WatchRoom
    /// The preparing card: Player ready / Loading playback… while the room waits.
    var preparing = false

    #if os(tvOS)
    private let avatar: CGFloat = 56
    private let nameFont = Font.system(size: 30, weight: .semibold)
    private let stateFont = Font.system(size: 24)
    #else
    private let avatar: CGFloat = 36
    private let nameFont = Font.body.weight(.semibold)
    private let stateFont = Font.subheadline
    #endif

    var body: some View {
        HStack(spacing: avatar * 0.35) {
            Circle()
                .fill(member.color.flatMap { Color(hex: $0) } ?? .gray)
                .frame(width: avatar, height: avatar)
                .overlay(Text(member.initial).font(.system(size: avatar * 0.45, weight: .heavy)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(member.isCreator ? "\(member.name) · Host" : member.name).font(nameFont).lineLimit(1)
                Text(stateText).font(stateFont).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle()
                .fill(member.present ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
                .opacity(member.joined ? 1 : 0)
        }
        .opacity(!member.joined || !member.present ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    var stateText: String {
        if !member.joined { return String(localized: "Invited · Not joined") }
        if preparing, room.waitingForReady {
            return member.ready ? String(localized: "Player ready") : String(localized: "Loading playback…")
        }
        var parts = [member.present ? String(localized: "Present") : String(localized: "Away")]
        if member.buffering { parts.append(String(localized: "Buffering")) }
        if room.status == .lobby, !member.isCreator {
            parts.append(member.ready ? String(localized: "Ready") : String(localized: "Not ready"))
        } else if room.waitingForReady {
            parts.append(member.ready ? String(localized: "Player ready") : String(localized: "Loading"))
        }
        if member.isGuest { parts.append(String(localized: "Guest")) }
        return parts.joined(separator: " · ")
    }
}
