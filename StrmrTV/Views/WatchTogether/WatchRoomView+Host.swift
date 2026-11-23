import SwiftUI

/// The host's side of the TV lobby: the external guest link (QR code, short code and URL,
/// create or revoke) and account invitations (invite by username, pending list with revoke).
extension WatchRoomView {
    var hostPanel: some View {
        VStack(alignment: .leading, spacing: 30) {
            externalSection
            accountSection
        }
        .focusSection()
    }

    @ViewBuilder
    private var externalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("External Guests").font(.headline)
            if let invite = model.externalInvitation {
                let link = APIClient.shared.publicURL(invite.url)
                HStack(alignment: .top, spacing: 24) {
                    QRCodeView(value: link, size: 220)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scan, or go to").font(.callout).foregroundStyle(.secondary)
                        Text(APIClient.shared.publicURL(invite.landingUrl)).font(.callout).lineLimit(2)
                        Text("and enter").font(.callout).foregroundStyle(.secondary)
                        Text(invite.shortCode).font(.system(size: 44, weight: .bold, design: .monospaced))
                    }
                }
                Button { Task { await model.revokeExternalInvitation() } } label: {
                    Label("Disable Link", systemImage: "xmark.circle")
                }
                .disabled(model.busy)
            } else if AppSession.shared.profile?.allowShareLinks == true {
                Text("Guests without an account can join in a web browser.").font(.callout).foregroundStyle(.secondary)
                Button { Task { await model.createExternalInvitation() } } label: {
                    Label("Create Guest Link", systemImage: "qrcode")
                }
                .disabled(model.busy)
            } else {
                Text("This profile can't create share links.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Other Accounts").font(.headline)
            Button {
                accountName = ""
                invitingAccount = true
            } label: {
                Label("Invite by Username…", systemImage: "person.badge.plus")
            }
            .disabled(model.busy)
            ForEach(model.pendingAccountInvites) { invite in
                Button { Task { await model.revoke(invite) } } label: {
                    HStack {
                        Text(invite.inviteeUsername ?? String(localized: "Invited account"))
                        Spacer()
                        Text("Pending · Revoke").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
