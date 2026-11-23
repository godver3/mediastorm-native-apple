import SwiftUI

/// TV: who to watch with (details › More › Watch Together…). This account's other profiles as
/// toggles, an optional account username, and the external guest link when the profile may share
/// links. Create Room makes the room and hands its lobby route back.
struct WatchTogetherPickerView: View {
    let target: DetailsTarget
    let logoURL: String?
    let overview: String?
    let onCreated: (WatchRoomRoute) -> Void
    @StateObject private var model = WatchTogetherCreateModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Backdrop(url: Artwork.url(target.backdropURL))
                .overlay(Color.black.opacity(0.75))
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Watch Together").font(.title2.weight(.bold))
                    Text("Who do you want to invite to watch \(target.name)?")
                        .font(.headline).foregroundStyle(.secondary)
                    profiles
                    TextField("Another account's username (optional)", text: $model.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 900)
                    if model.canInviteExternal {
                        Button { model.externalGuests.toggle() } label: {
                            Label("External guests via share link",
                                  systemImage: model.externalGuests ? "checkmark.square.fill" : "square")
                        }
                    }
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                    HStack(spacing: 30) {
                        Button {
                            Task { await model.create(target, logoURL: logoURL, overview: overview) }
                        } label: {
                            Label(model.createLabel, systemImage: "person.2.fill")
                        }
                        .disabled(model.creating)
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
                .padding(80)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await model.prepare() }
        .onChange(of: model.created) { _, route in
            if let route { onCreated(route) }
        }
    }

    @ViewBuilder
    private var profiles: some View {
        let candidates = model.candidates
        if candidates.isEmpty {
            Text("No other profiles on this account. Invite another account by username, or create the room and share its link.")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 40) {
                    ForEach(candidates) { profile in
                        let picked = model.invitees.contains(profile.id)
                        Button { model.toggle(profile) } label: {
                            VStack(spacing: 14) {
                                ProfileAvatar(profile: profile, size: 150)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 44)).foregroundStyle(picked ? .green : .white)
                                    }
                                Text(profile.name).font(.headline)
                            }
                            .padding(20)
                        }
                        .cardLift()
                        .accessibilityValue(picked ? "Invited" : "Not invited")
                    }
                }
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }
}
