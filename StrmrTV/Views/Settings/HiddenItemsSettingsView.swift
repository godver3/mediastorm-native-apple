import SwiftUI

/// Settings › Hidden Items: titles hidden from Continue Watching and titles hidden from
/// the profile, each row a button that brings its title back. Focus moves to the next
/// row (or the section's empty state) when one leaves, so the remote never loses it.
struct HiddenItemsSettingsView: View {
    @EnvironmentObject private var titles: TitleStateStore
    @StateObject private var model = HiddenItemsModel()
    @FocusState private var focus: Row?

    enum Row: Hashable {
        case continueItem(HiddenItem), continueEmpty, profileItem(HiddenItem), profileEmpty
    }

    var body: some View {
        Form {
            SettingsPageTitle("Hidden Items")
            Section {
                switch model.continueState {
                case .loading where model.continueItems.isEmpty: StatusRow(text: String(localized: "Loading…"))
                case let .failed(message) where model.continueItems.isEmpty: retryRow(message)
                default:
                    if model.continueItems.isEmpty {
                        StatusRow(text: String(localized: "Nothing is hidden from Continue Watching."))
                            .focused($focus, equals: .continueEmpty)
                    }
                    ForEach(model.continueItems) { item in
                        HiddenItemRow(item: item, action: String(localized: "Show")) { showInContinueWatching(item) }
                            .focused($focus, equals: .continueItem(item))
                            .accessibilityHint(Text("Puts the title back in Continue Watching"))
                    }
                }
            } header: {
                Text("Continue Watching")
            } footer: {
                Text("Titles you hid from Continue Watching. A hidden title also comes back when you play it again.")
            }
            Section {
                switch model.profileState {
                case .loading where titles.hidden.isEmpty: StatusRow(text: String(localized: "Loading…"))
                case let .failed(message) where titles.hidden.isEmpty: retryRow(message)
                default:
                    if titles.hidden.isEmpty {
                        StatusRow(text: String(localized: "Nothing is hidden from this profile."))
                            .focused($focus, equals: .profileEmpty)
                    }
                    ForEach(titles.hidden) { item in
                        HiddenItemRow(item: item, action: String(localized: "Unhide")) { unhideFromProfile(item) }
                            .focused($focus, equals: .profileItem(item))
                            .accessibilityHint(Text("Shows the title on Home and in lists again"))
                    }
                }
            } header: {
                Text("Hidden from Profile")
            } footer: {
                Text("Titles hidden from this profile are left out of Home rows and lists.")
            }
        }
        .settingsSubpage()
        .settingsListMargins(80)
        .task { await model.load(titles: titles) }
    }

    private func retryRow(_ message: String) -> some View {
        Button { Task { await model.load(titles: titles) } } label: {
            LabeledContent("Couldn't Load") { Text("Try Again") }
        }
        .accessibilityValue(Text(message))
    }

    private func showInContinueWatching(_ item: HiddenItem) {
        let next = HiddenItemsModel.neighbour(of: item, in: model.continueItems)
        Task {
            await model.showInContinueWatching(item, titles: titles)
            guard !model.continueItems.contains(item) else { return }
            focus = next.map(Row.continueItem) ?? .continueEmpty
        }
    }

    private func unhideFromProfile(_ item: HiddenItem) {
        let next = HiddenItemsModel.neighbour(of: item, in: titles.hidden)
        Task {
            await model.unhideFromProfile(item, titles: titles)
            guard !titles.hidden.contains(item) else { return }
            focus = next.map(Row.profileItem) ?? .profileEmpty
        }
    }
}

/// A hidden title: poster, name and year, and what selecting it does.
private struct HiddenItemRow: View {
    let item: HiddenItem
    let action: String
    let perform: () -> Void

    private static let poster = CGSize(width: 60, height: 90)

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 28) {
                RemoteImage(url: Artwork.url(item.posterUrl, size: "w185"), size: Self.poster) { _ in
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: item.isMovie ? "film" : "tv").foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName).lineLimit(1)
                    Text(item.displayDetail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 20)
                Text(action).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel(Text(item.displayName))
        .accessibilityValue(Text("\(item.displayDetail). \(action)"))
    }
}

/// A focusable message row (loading, empty), so the remote can rest on an empty section.
private struct StatusRow: View {
    let text: String

    var body: some View {
        Button {} label: { Text(text).foregroundStyle(.secondary) }
    }
}
