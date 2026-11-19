import Foundation

/// Settings › Hidden Items on both platforms: titles hidden from Continue Watching (the
/// row's own hide, read here only) and titles hidden from the profile (kept in
/// `TitleStateStore.hidden`, so the long-press menus and the Lists tab stay in step).
@MainActor
final class HiddenItemsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading, loaded, failed(String)
    }

    @Published private(set) var continueItems: [HiddenItem] = []
    @Published private(set) var continueState: LoadState = .loading
    @Published private(set) var profileState: LoadState = .loading

    private let api = APIClient.shared
    private let log = AppLog(category: "titles")

    func load(titles: TitleStateStore) async {
        async let cw: Void = loadContinueWatching()
        async let profile: Void = loadProfile(titles: titles)
        _ = await (cw, profile)
    }

    private func loadContinueWatching() async {
        if continueItems.isEmpty { continueState = .loading }
        do {
            continueItems = try await api.continueWatchingHidden()
            continueState = .loaded
        } catch {
            log.error("hidden from Continue Watching failed to load: \(error.localizedDescription)")
            continueState = .failed(error.localizedDescription)
        }
    }

    /// Reads the profile's hidden titles into the shared store (whose own refresh drops
    /// errors), so a failure can be shown here.
    private func loadProfile(titles: TitleStateStore) async {
        if titles.hidden.isEmpty { profileState = .loading }
        do {
            titles.hidden = try await api.hiddenItems()
            titles.hiddenLoaded = true
            profileState = .loaded
        } catch {
            log.error("hidden items failed to load: \(error.localizedDescription)")
            profileState = titles.hiddenLoaded ? .loaded : .failed(error.localizedDescription)
        }
    }

    /// Puts a title back in Continue Watching. It leaves the list at once and comes back
    /// if the server refuses; Home's row reloads on the API's notice.
    func showInContinueWatching(_ item: HiddenItem, titles: TitleStateStore) async {
        guard let index = continueItems.firstIndex(of: item) else { return }
        continueItems.remove(at: index)
        do {
            try await api.unhideFromContinueWatching(seriesID: item.id)
            log.notice("unhid \(item.id) from Continue Watching")
            titles.show(toast: String(localized: "Back in Continue Watching"))
        } catch {
            log.error("unhide \(item.id) from Continue Watching failed: \(error.localizedDescription)")
            continueItems.insert(item, at: min(index, continueItems.count))
            titles.show(toast: String(localized: "Failed to show in Continue Watching"))
        }
    }

    /// The title menus' Unhide: the store toasts and tells Home and the lists.
    func unhideFromProfile(_ item: HiddenItem, titles: TitleStateStore) async {
        await titles.unhide(item)
    }

    /// The row a list should focus or scroll to once `item` leaves it: the next one,
    /// else the one before, else none (the section's empty state).
    static func neighbour(of item: HiddenItem, in items: [HiddenItem]) -> HiddenItem? {
        guard let index = items.firstIndex(of: item) else { return nil }
        if index + 1 < items.count { return items[index + 1] }
        return index > 0 ? items[index - 1] : nil
    }
}

extension HiddenItem {
    /// The title, or a placeholder when the server had no metadata for it.
    var displayName: String {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return String(localized: "Unknown title")
        }
        return name
    }

    /// "2016 · Series"; the raw ID when the name is missing, so the row can still be told apart.
    var displayDetail: String {
        var parts: [String] = []
        if let year, year > 0 { parts.append(String(year)) }
        parts.append(isMovie ? String(localized: "Movie") : String(localized: "Series"))
        if name?.trimmingCharacters(in: .whitespaces).isEmpty ?? true { parts.append(id) }
        return parts.joined(separator: " · ")
    }
}
