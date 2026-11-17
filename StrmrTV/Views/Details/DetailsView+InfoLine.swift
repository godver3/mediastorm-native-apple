import SwiftUI

extension DetailsView {
    // MARK: Info lines (under the actions)

    /// The prequeued release's name, then on the next line the tracks Play will use, each led
    /// by its symbol ("🔊 English · E-AC-3   💬 English"); each behind its own profile display
    /// setting (`DetailsInfoLineStore`). Sized as the metadata line and coloured as on Android
    /// TV; it takes the actions' focus captions' place, which hide while it shows.
    @ViewBuilder
    var infoLine: some View {
        let parts = infoLineParts
        if parts.shown {
            VStack(alignment: .leading, spacing: 6) {
                if parts.loading {
                    HStack(spacing: 0) {
                        ProgressView().scaleEffect(0.6).frame(width: 30, height: 26)
                            .padding(.trailing, 10)
                        Text("Finding a source…").fixedSize()
                    }
                } else if let filename = parts.filename {
                    // The release name gives way first, from the middle, so its tail
                    // (quality, group) stays readable.
                    Text(filename).lineLimit(1).truncationMode(.middle)
                }
                if let tracks = parts.tracks {
                    HStack(spacing: 32) {
                        if let audio = tracks.audio {
                            Label(audio, systemImage: "speaker.wave.2.fill")
                        }
                        Label(tracks.subtitle ?? String(localized: "Off"), systemImage: "captions.bubble.fill")
                    }
                    .labelStyle(InfoLineLabelStyle())
                    .lineLimit(1).fixedSize()
                }
            }
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: 1520, alignment: .leading)
            .animation(.easeInOut(duration: 0.2), value: parts.loading)
        }
    }

    /// The lines' parts: still finding a source, the release name, and the tracks.
    var infoLineParts: InfoLineParts {
        let store = infoLineStore
        return InfoLineParts(
            loading: store.showFilename && warmPrequeue != nil && warmPrequeue?.status == nil,
            filename: store.showFilename ? warmPrequeue?.status?.releaseTitle : nil,
            tracks: store.showSelectedTracks ? selectedTracks : nil)
    }

    /// Whether the lines show; the actions' focus captions (Play's "From x:xx" among them) then hide.
    var infoLineShown: Bool { infoLineParts.shown }
}

struct InfoLineParts {
    var loading: Bool
    var filename: String?
    var tracks: (audio: String?, subtitle: String?)?

    var shown: Bool { loading || filename != nil || tracks != nil }
}

/// A track's symbol before its name, at the text's size.
private struct InfoLineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.font(.system(size: 22, weight: .semibold))
            configuration.title
        }
    }
}
