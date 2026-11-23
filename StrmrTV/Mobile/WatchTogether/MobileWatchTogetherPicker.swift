#if os(iOS)
import SwiftUI

/// Phone: who to watch with (details › More › Watch Together…), as a native form sheet: this
/// account's other profiles, an optional account username, and the external guest link when the
/// profile may share links.
struct MobileWatchTogetherPicker: View {
    let target: DetailsTarget
    let logoURL: String?
    let overview: String?
    let onCreated: (WatchRoomRoute) -> Void
    @StateObject private var model = WatchTogetherCreateModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.candidates.isEmpty {
                        Text("No other profiles on this account.").foregroundStyle(.secondary)
                    }
                    ForEach(model.candidates) { profile in
                        Button { model.toggle(profile) } label: {
                            HStack(spacing: 12) {
                                ProfileAvatar(profile: profile, size: 36)
                                Text(profile.name).foregroundStyle(.primary)
                                Spacer()
                                if model.invitees.contains(profile.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Profiles")
                }
                Section {
                    TextField("Username (optional)", text: $model.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Another Account")
                }
                if model.canInviteExternal {
                    Section {
                        Toggle("External guests via share link", isOn: $model.externalGuests)
                    } footer: {
                        Text("Guests without an account join in a web browser with a link, QR code or short code.")
                    }
                }
                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await model.create(target, logoURL: logoURL, overview: overview) }
                    } label: {
                        Text(model.createLabel).frame(maxWidth: .infinity)
                    }
                    .disabled(model.creating)
                }
            }
            .navigationTitle("Watch Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task { await model.prepare() }
        .onChange(of: model.created) { _, route in
            if let route { onCreated(route) }
        }
    }
}
#endif
