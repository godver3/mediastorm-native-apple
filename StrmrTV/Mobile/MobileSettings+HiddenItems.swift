#if os(iOS)
import SwiftUI

/// Settings › Hidden Items on the phone: titles hidden from Continue Watching and from the
/// profile, each with a button (or a swipe) that brings it back. Same model as the TV's page.
struct MobileHiddenItemsView: View {
    @EnvironmentObject private var titles: TitleStateStore
    @StateObject private var model = HiddenItemsModel()

    var body: some View {
        List {
            Section {
                section(state: model.continueState, items: model.continueItems,
                        empty: String(localized: "Nothing is hidden from Continue Watching."),
                        action: String(localized: "Show")) { item in
                    await model.showInContinueWatching(item, titles: titles)
                }
            } header: {
                Text("Continue Watching")
            } footer: {
                Text("Titles you hid from Continue Watching. A hidden title also comes back when you play it again.")
            }
            Section {
                section(state: model.profileState, items: titles.hidden,
                        empty: String(localized: "Nothing is hidden from this profile."),
                        action: String(localized: "Unhide")) { item in
                    await model.unhideFromProfile(item, titles: titles)
                }
            } header: {
                Text("Hidden from Profile")
            } footer: {
                Text("Titles hidden from this profile are left out of Home rows and lists.")
            }
        }
        .navigationTitle("Hidden Items")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(titles: titles) }
        .refreshable { await model.load(titles: titles) }
    }

    @ViewBuilder
    private func section(state: HiddenItemsModel.LoadState, items: [HiddenItem], empty: String, action: String,
                         perform: @escaping (HiddenItem) async -> Void) -> some View {
        switch state {
        case .loading where items.isEmpty:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading…").foregroundStyle(.secondary)
            }
        case .failed where items.isEmpty:
            Button {
                Task { await model.load(titles: titles) }
            } label: {
                LabeledContent("Couldn't Load") { Text("Try Again") }
            }
        default:
            if items.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                MobileHiddenItemRow(item: item, action: action) { Task { await perform(item) } }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(action) { Task { await perform(item) } }.tint(.accentColor)
                    }
            }
        }
    }
}

/// A hidden title: poster, name and year, and the button that brings it back.
private struct MobileHiddenItemRow: View {
    let item: HiddenItem
    let action: String
    let perform: () -> Void

    private static let poster = CGSize(width: 40, height: 60)

    var body: some View {
        HStack(spacing: 14) {
            RemoteImage(url: Artwork.url(item.posterUrl, size: "w185"), size: Self.poster) { _ in
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: item.isMovie ? "film" : "tv").font(.caption).foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).lineLimit(1)
                Text(item.displayDetail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action, action: perform)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text("\(action) \(item.displayName)"))
        }
        .padding(.vertical, 2)
    }
}
#endif
