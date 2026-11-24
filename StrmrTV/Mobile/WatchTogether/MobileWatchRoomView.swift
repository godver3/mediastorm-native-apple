#if os(iOS)
import SwiftUI

/// Phone: a watch room's lobby, as an inset grouped list (the Expo `watch-room` screen):
/// status and actions, members, then the host's external guest link and account invitations.
/// The back button ends the room for its host and leaves it for others (after asking).
struct MobileWatchRoomView: View {
    let route: WatchRoomRoute
    @StateObject private var model: WatchRoomLobbyModel
    @Environment(\.dismiss) private var dismiss
    @State private var accountName = ""
    @State private var confirmingExit = false

    init(route: WatchRoomRoute) {
        self.route = route
        _model = StateObject(wrappedValue: WatchRoomLobbyModel(route: route))
    }

    /// Leaving the screen means leaving the room, so the system back button is replaced.
    private var asksBeforeLeaving: Bool { !model.ended && model.room != nil && model.accountInvitation == nil }

    var body: some View {
        List {
            Section {
                Text(model.title).font(.title3.weight(.bold))
                if let invite = model.accountInvitation {
                    Text("\(invite.creatorName) invited your account to watch together.").foregroundStyle(.secondary)
                    Button("Accept") { Task { await model.acceptInvitation() } }
                    Button("Decline", role: .destructive) { Task { await model.declineInvitation() } }
                } else if let room = model.room {
                    Text(model.ended ? room.endReasonText : statusLine(room)).foregroundStyle(.secondary)
                    if !model.ended { actions }
                } else if model.ended {
                    Text("This watch room has ended.").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
            .disabled(model.busy)
            if let room = model.room {
                Section("Members") {
                    ForEach(room.members) { WatchRoomMemberRow(member: $0, room: room) }
                }
            }
            if model.isHost, !model.ended { hostSections }
        }
        .navigationTitle("Watch Together")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(asksBeforeLeaving)
        .toolbar {
            if asksBeforeLeaving {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.isHost ? "End" : "Leave") { confirmingExit = true }
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.closed) { _, closed in if closed { dismiss() } }
        .confirmationDialog(model.isHost ? "End this watch room for everyone?" : "Leave this watch room?",
                            isPresented: $confirmingExit, titleVisibility: .visible) {
            Button(model.isHost ? "End Room" : "Leave Room", role: .destructive) { Task { await model.exit() } }
            Button("Stay", role: .cancel) {}
        }
    }

    private func statusLine(_ room: WatchRoom) -> String {
        switch room.status {
        case .lobby:
            model.isHost ? String(localized: "Start when everyone is here.")
                : String(localized: "Waiting for \(room.creatorName) to start.")
        case .playing, .paused: String(localized: "Playback has started.")
        case .ended: room.endReasonText
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.isPlaying {
            Button { model.openTitle() } label: { Label(model.opened ? "Rejoin" : "Join", systemImage: "play.fill") }
            if let episode = model.hostEpisodeText { Text(episode).foregroundStyle(.secondary) }
        } else if model.isHost {
            Button { Task { await model.startPlayback() } } label: { Label("Start", systemImage: "play.fill") }
        } else if let me = model.me {
            Button { Task { await model.toggleReady() } } label: {
                Label(me.ready ? "Not Ready" : "Ready", systemImage: me.ready ? "xmark.circle" : "checkmark.circle")
            }
        }
    }

    @ViewBuilder
    private var hostSections: some View {
        Section {
            if let invite = model.externalInvitation {
                let link = APIClient.shared.publicURL(invite.url)
                HStack {
                    Spacer()
                    QRCodeView(value: link, size: 200)
                    Spacer()
                }
                LabeledContent("Code", value: invite.shortCode).font(.body.monospaced())
                ShareLink(item: link) { Label("Share Link", systemImage: "square.and.arrow.up") }
                Button("Disable Link", role: .destructive) { Task { await model.revokeExternalInvitation() } }
            } else if AppSession.shared.profile?.allowShareLinks == true {
                Button { Task { await model.createExternalInvitation() } } label: {
                    Label("Create Guest Link", systemImage: "qrcode")
                }
            } else {
                Text("This profile can't create share links.").foregroundStyle(.secondary)
            }
        } header: {
            Text("External Guests")
        } footer: {
            if let invite = model.externalInvitation {
                Text("Or open \(APIClient.shared.publicURL(invite.landingUrl)) and enter the code.")
            }
        }
        .disabled(model.busy)
        Section("Other Accounts") {
            HStack {
                TextField("Username", text: $accountName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Invite") {
                    let name = accountName
                    accountName = ""
                    Task { await model.inviteAccount(name) }
                }
                .disabled(accountName.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
            }
            ForEach(model.pendingAccountInvites) { invite in
                HStack {
                    Text(invite.inviteeUsername ?? String(localized: "Invited account"))
                    Spacer()
                    Button("Revoke", role: .destructive) { Task { await model.revoke(invite) } }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}
#endif
