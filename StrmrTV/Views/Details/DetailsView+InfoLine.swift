import SwiftUI

extension DetailsView {
    // MARK: Info line (under the actions)

    /// "FILENAME · RUNTIME · English · E-AC-3 · English Subtitles", each part behind its own
    /// profile display setting (`DetailsInfoLineStore`); nothing when every shown part is empty.
    /// Sized as the metadata line and coloured as on Android TV; it takes the actions' focus
    /// captions' place, which hide while it shows.
    @ViewBuilder
    var infoLine: some View {
        let (loading, filename, rest) = infoLineParts
        if loading || filename != nil || !rest.isEmpty {
            HStack(spacing: 0) {
                if loading {
                    ProgressView().scaleEffect(0.6).frame(width: 30, height: 26)
                        .padding(.trailing, 10)
                    Text("Finding a source…").fixedSize()
                } else if let filename {
                    // The release name gives way first, from the middle, so its tail
                    // (quality, group) stays readable.
                    Text(filename).lineLimit(1).truncationMode(.middle)
                }
                if !rest.isEmpty {
                    Text(((loading || filename != nil) ? " · " : "") + rest.joined(separator: " · "))
                        .lineLimit(1).fixedSize()
                }
            }
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: 1520, alignment: .leading)
            .animation(.easeInOut(duration: 0.2), value: loading)
        }
    }

    /// The line's segments: still finding a source, the release name, then runtime and tracks.
    var infoLineParts: (loading: Bool, filename: String?, rest: [String]) {
        let store = infoLineStore
        let loading = store.showFilename && warmPrequeue != nil && warmPrequeue?.status == nil
        let filename = store.showFilename ? warmPrequeue?.status?.releaseTitle : nil
        let rest = [store.showRuntime ? infoLineRuntime : nil,
                    store.showSelectedTracks && warmPrequeue?.status != nil ? tracksCaption : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return (loading, filename, rest)
    }

    /// Whether the line shows; the actions' focus captions (Play's "From x:xx" among them) then hide.
    var infoLineShown: Bool {
        let (loading, filename, rest) = infoLineParts
        return loading || filename != nil || !rest.isEmpty
    }

    /// The episode Play targets; a movie's runtime is already in the metadata line.
    var infoLineRuntime: String? {
        target.isMovie ? nil : formatRuntime(primaryEpisode?.runtimeMinutes)
    }
}
