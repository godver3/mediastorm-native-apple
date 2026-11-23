import Foundation

/// The details page's Watch Together picker (the Expo `details` picker): this account's other
/// profiles to invite, an optional other account by username, and (with the profile's share-link
/// permission) an external guest link. Creating the room opens its lobby.
@MainActor
final class WatchTogetherCreateModel: ObservableObject {
    @Published var invitees: Set<String> = []
    @Published var username = ""
    @Published var externalGuests = false
    @Published private(set) var creating = false
    @Published var error: String?
    /// Set once the room exists: the screen opens its lobby.
    @Published var created: WatchRoomRoute?

    private let session = AppSession.shared

    /// Profiles of this account other than the current one.
    var candidates: [Profile] {
        let me = session.profile
        return session.profiles.filter { $0.id != me?.id && ($0.accountId == nil || $0.accountId == me?.accountId) }
    }

    var canInviteExternal: Bool { session.profile?.allowShareLinks == true }

    func toggle(_ profile: Profile) {
        if invitees.contains(profile.id) { invitees.remove(profile.id) } else { invitees.insert(profile.id) }
    }

    var createLabel: String {
        let account = username.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1
        let count = invitees.count + account
        if creating { return String(localized: "Creating Room…") }
        if count == 0 { return externalGuests ? String(localized: "Create Room for External Guests") : String(localized: "Create Room") }
        return externalGuests ? String(localized: "Create Room (\(count) invited + link)")
            : String(localized: "Create Room (\(count) invited)")
    }

    /// Loads the account's profiles when the app started on a remembered one and never listed them.
    func prepare() async {
        guard session.profiles.isEmpty else { return }
        try? await session.loadProfiles()
        objectWillChange.send()
    }

    func reset() {
        invitees = []
        username = ""
        externalGuests = false
        error = nil
        created = nil
    }

    /// Creates the room for `target` (`logoURL` / `overview` from the loaded details), invites
    /// the account named, and hands the lobby route back through `created`.
    func create(_ target: DetailsTarget, logoURL: String?, overview: String?) async {
        guard !creating else { return }
        creating = true
        defer { creating = false }
        let params = WatchRoom.params(for: target, logoURL: logoURL, overview: overview)
        let create = WatchRoomCreate(title: target.name, mediaType: target.isMovie ? "movie" : "series",
                                     itemId: target.titleID, posterUrl: target.posterURL,
                                     backdropUrl: target.backdropURL ?? target.posterURL, params: params,
                                     inviteeProfileIds: invitees.sorted())
        do {
            let room = try await APIClient.shared.createWatchRoom(create)
            WatchTogetherSession.shared.setActive(room)
            let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !account.isEmpty {
                do {
                    _ = try await APIClient.shared.inviteAccount(account, to: room.id)
                } catch {
                    // The room stands; the lobby can invite again.
                    self.error = String(localized: "Room created, but the account invite failed: \(error.localizedDescription)")
                }
            }
            created = WatchRoomRoute(roomID: room.id, createExternalInvite: externalGuests && canInviteExternal)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
