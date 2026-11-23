import SwiftUI

/// TV: a watch room's lobby (the Expo `watch-room` screen). Members with their joined, present,
/// ready and buffering state; Ready for guests, Start for the host; Join Playback once playing.
/// The host's invitations and external guest link are on the right (`+Host`). Back (Menu) ends
/// the room for the host and leaves it for others; an account invitation is accepted or
/// declined first.
struct WatchRoomView: View {
    let route: WatchRoomRoute
    @StateObject var model: WatchRoomLobbyModel
    @Environment(\.dismiss) var dismiss
    @State var invitingAccount = false
    @State var accountName = ""
    @State var confirmingExit = false

    init(route: WatchRoomRoute) {
        self.route = route
        _model = StateObject(wrappedValue: WatchRoomLobbyModel(route: route))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(url: Artwork.url(model.backdropURL))
                .overlay(Color.black.opacity(0.78))
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 80) {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if model.accountInvitation != nil {
                        invitationActions
                    } else if let room = model.room {
                        if model.ended { endedActions(room) } else { actions(room) }
                        members(room)
                    } else if model.ended {
                        endedActions(nil)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.isHost, !model.ended {
                    hostPanel.frame(width: 640)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onExitCommand(perform: backPressed)
        .onChange(of: model.closed) { _, closed in if closed { dismiss() } }
        .alert("Invite an Account", isPresented: $invitingAccount) {
            TextField("Username", text: $accountName)
            Button("Invite") { Task { await model.inviteAccount(accountName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They see the invitation on their Home screen.")
        }
        .confirmationDialog(model.isHost ? "End this watch room for everyone?" : "Leave this watch room?",
                            isPresented: $confirmingExit, titleVisibility: .visible) {
            Button(model.isHost ? "End Room" : "Leave Room", role: .destructive) { Task { await model.exit() } }
            Button("Stay", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WATCH TOGETHER").font(.caption.weight(.bold)).foregroundStyle(Color(red: 0.58, green: 0.77, blue: 0.99))
            Text(model.title).font(.title2.weight(.bold)).lineLimit(2)
            if let invite = model.accountInvitation {
                Text("\(invite.creatorName) invited your account to watch together.").foregroundStyle(.secondary)
            } else if let room = model.room {
                Text(statusLine(room)).foregroundStyle(.secondary)
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
    }

    private func statusLine(_ room: WatchRoom) -> String {
        if model.ended { return room.endReasonText }
        switch room.status {
        case .lobby:
            return model.isHost ? String(localized: "Start when everyone is here.")
                : String(localized: "Waiting for \(room.creatorName) to start.")
        case .playing, .paused:
            return String(localized: "Playback has started.")
        case .ended:
            return room.endReasonText
        }
    }

    private var invitationActions: some View {
        HStack(spacing: 30) {
            Button { Task { await model.acceptInvitation() } } label: { Label("Accept", systemImage: "checkmark") }
            Button(role: .destructive) { Task { await model.declineInvitation() } } label: {
                Label("Decline", systemImage: "xmark")
            }
        }
        .disabled(model.busy)
    }

    private func actions(_ room: WatchRoom) -> some View {
        HStack(spacing: 30) {
            if model.isPlaying {
                Button { model.openTitle() } label: { Label(model.opened ? "Rejoin Playback" : "Join Playback", systemImage: "play.fill") }
            } else if model.isHost {
                Button { Task { await model.startPlayback() } } label: { Label("Start", systemImage: "play.fill") }
            } else if let me = model.me {
                Button { Task { await model.toggleReady() } } label: {
                    Label(me.ready ? "Not Ready" : "Ready", systemImage: me.ready ? "xmark.circle" : "checkmark.circle")
                }
            }
            Button { confirmingExit = true } label: {
                Label(model.isHost ? "End Room" : "Leave", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .disabled(model.busy)
    }

    private func endedActions(_ room: WatchRoom?) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // The header's status line already says why, once the room is known.
            if room == nil { Text("This watch room has ended.").font(.headline) }
            Button("Close") { dismiss() }
        }
    }

    private func members(_ room: WatchRoom) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Members").font(.headline)
            ForEach(room.members) { WatchRoomMemberRow(member: $0, room: room) }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    /// Back ends the room for its host and leaves it for others (after asking); an ended room,
    /// or an invitation not yet accepted, just closes.
    private func backPressed() {
        if model.ended || model.room == nil || model.accountInvitation != nil {
            dismiss()
        } else {
            confirmingExit = true
        }
    }
}
