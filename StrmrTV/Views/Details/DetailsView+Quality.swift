import SwiftUI

/// Quality: the quality preset Play and Choose Source rank this title's releases with, on
/// servers that offer presets for it (`QualityPresetStore`). A menu of the offered presets in
/// the server's order, the default marked, the current one checked; the server remembers a
/// pick for the title on this device. Starts in More Options (Customize Buttons can move it
/// into the row); without offered presets it is hidden everywhere.
extension DetailsView {
    var qualityChoices: QualityPresetChoices? { qualityPresets.choices(for: target) }

    /// "Quality: German HD".
    var qualityLabel: String {
        qualityChoices?.label(isMovie: target.isMovie, picked: qualityPresets.picked(titleID: target.titleID))
            ?? String(localized: "Quality")
    }

    /// Actions this title doesn't offer, left out of Customize Buttons.
    var unofferedActions: Set<DetailsAction> { qualityChoices == nil ? [.quality] : [] }

    @ViewBuilder
    var qualityMenuItems: some View {
        if let choices = qualityChoices {
            let active = choices.activeID(isMovie: target.isMovie, picked: qualityPresets.picked(titleID: target.titleID))
            let defaultID = choices.defaultSelection(isMovie: target.isMovie).id
            Section {
                ForEach(choices.offered(isMovie: target.isMovie)) { preset in
                    let name = preset.id == defaultID ? String(localized: "\(preset.name) (default)") : preset.name
                    Button { qualityPresets.pick(preset.id, for: target) } label: {
                        if preset.id == active { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            } header: {
                Text("Remembered for this title on this device.")
            }
        }
    }

    /// In the row: icon-only, its caption naming the preset.
    @ViewBuilder
    var qualityButton: some View {
        if qualityChoices != nil {
            Menu { qualityMenuItems } label: {
                Label(qualityLabel, systemImage: DetailsAction.quality.symbol).labelStyle(.iconOnly)
            }
            .focused($focus, equals: .action(.quality))
            .focusCaption(qualityLabel, shown: focus == .action(.quality))
        }
    }

    /// In More Options.
    @ViewBuilder
    var qualityMoreItem: some View {
        if qualityChoices != nil {
            Menu { qualityMenuItems } label: { Label(qualityLabel, systemImage: DetailsAction.quality.symbol) }
        }
    }
}
