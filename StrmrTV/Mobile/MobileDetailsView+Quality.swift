#if os(iOS)
import SwiftUI

/// Quality in the More menu: the quality preset Play and Choose Source rank this title with,
/// as the TV page's Quality menu (`DetailsView+Quality`). Hidden without offered presets.
extension MobileDetailsView {
    @ViewBuilder
    var qualityMenu: some View {
        if let choices = qualityPresets.choices(for: target) {
            let picked = qualityPresets.picked(titleID: target.titleID)
            let active = choices.activeID(isMovie: target.isMovie, picked: picked)
            let defaultID = choices.defaultSelection(isMovie: target.isMovie).id
            Menu {
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
            } label: {
                Label(choices.label(isMovie: target.isMovie, picked: picked), systemImage: "dial.medium")
            }
        }
    }
}
#endif
