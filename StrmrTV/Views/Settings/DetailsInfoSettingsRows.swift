import SwiftUI

/// Settings › Details rows for this device's overrides of the info line under the details
/// actions (`DetailsInfoLineStore`): each has "Default (…)", the profile's value, then On and Off.
struct DetailsInfoSettingsRows: View {
    @ObservedObject private var store = DetailsInfoLineStore.shared

    private static let onOff: [ChoiceRow<Bool>.Choice] = [
        .init(value: true, name: String(localized: "On")),
        .init(value: false, name: String(localized: "Off")),
    ]

    var body: some View {
        ChoiceRow(title: "Show Source Filename", selection: $store.filename,
                  defaultValue: store.server.showFilename ?? false, choices: Self.onOff)
            .accessibilityHint(Text("Names the release Play will use, under the buttons"))
        ChoiceRow(title: "Show Episode Runtime", selection: $store.runtime,
                  defaultValue: store.server.showRuntime ?? false, choices: Self.onOff)
            .accessibilityHint(Text("Shows the selected episode's runtime, under the buttons"))
        ChoiceRow(title: "Show Selected Tracks", selection: $store.selectedTracks,
                  defaultValue: store.server.showSelectedTracks ?? false, choices: Self.onOff)
            .accessibilityHint(Text("Shows the audio and subtitle tracks Play will use, under the buttons"))
    }
}
