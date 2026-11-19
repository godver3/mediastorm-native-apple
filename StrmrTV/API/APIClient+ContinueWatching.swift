import Foundation

/// Continue Watching, minus what the profile put aside, plus the hide action and its undo. Titles
/// hidden with `hideFromContinueWatching` are dropped server-side; the "Set Aside"
/// custom list is filtered here, as the other clients do.
extension APIClient {
    func continueWatching() async throws -> [ContinueWatchingItem] {
        // Lossy: an empty list arrives as `null`, and one bad item mustn't cost the row.
        async let rows: LossyArray<ContinueWatchingItem> = send("GET", "\(profilePath)/history/continue")
        async let setAside = setAsideItems()
        let items = try await rows.elements
        let aside = await setAside
        guard !aside.isEmpty else { return items }
        return items.filter { item in !aside.contains { $0.matches(item) } }
    }

    /// Drops a title from Continue Watching until it is played again, then posts
    /// `continueWatchingChanged` so every view of the row reloads.
    func hideFromContinueWatching(seriesID: String) async throws {
        #if DEBUG
        if DebugPrefill.dryRunHide { return }
        #endif
        try await sendRaw("POST", "\(profilePath)/history/continue/hide", jsonObject: ["seriesId": seriesID])
        await MainActor.run { NotificationCenter.default.post(name: .continueWatchingChanged, object: nil) }
    }

    /// Titles hidden from Continue Watching, newest first, in the shape of the profile's
    /// hidden items. Lossy, so one bad entry never costs the list.
    func continueWatchingHidden() async throws -> [HiddenItem] {
        let items: LossyArray<HiddenItem> = try await send("GET", "\(profilePath)/history/continue/hidden")
        return items.elements
    }

    /// Undoes `hideFromContinueWatching`: the title is back in the row if it still
    /// qualifies. Posts `continueWatchingChanged` so every view of the row reloads.
    func unhideFromContinueWatching(seriesID: String) async throws {
        try await sendRaw("POST", "\(profilePath)/history/continue/unhide", jsonObject: ["seriesId": seriesID])
        await MainActor.run { NotificationCenter.default.post(name: .continueWatchingChanged, object: nil) }
    }

    /// The "Set Aside" list's titles; none when the list is missing or unreadable, so
    /// a failure here never costs the row.
    private func setAsideItems() async -> [ListedTitle] {
        guard let lists: [CustomListSummary] = try? await send("GET", "\(profilePath)/custom-lists"),
              let list = lists.first(where: { $0.isSetAside })
        else { return [] }
        return (try? await send("GET", "\(profilePath)/custom-lists/\(Self.segment(list.id))/items")) ?? []
    }
}

extension Notification.Name {
    static let continueWatchingChanged = Notification.Name("StrmrTV.continueWatchingChanged")
}

private struct CustomListSummary: Decodable {
    let id: String
    let name: String

    var isSetAside: Bool {
        name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Set Aside") == .orderedSame
    }
}

/// A custom list entry, decoded only as far as matching needs.
private struct ListedTitle: Decodable {
    let id: String
    let mediaType: String
    let externalIds: [String: String]?

    /// Same kind, and the same ID or any shared provider ID.
    func matches(_ item: ContinueWatchingItem) -> Bool {
        guard (mediaType == "movie") == item.isMovie else { return false }
        if id.caseInsensitiveCompare(item.seriesId) == .orderedSame { return true }
        let theirs = item.externalIds ?? [:]
        return (externalIds ?? [:]).contains { key, value in
            let value = value.trimmingCharacters(in: .whitespaces).lowercased()
            return !value.isEmpty && value == theirs[key]?.trimmingCharacters(in: .whitespaces).lowercased()
        }
    }
}
