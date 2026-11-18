import SwiftUI
import UIKit

/// Settings › Playback: shows whether tvOS Match Content is on. The app follows Apple's
/// setting (Settings › Video and Audio › Match Content) for frame rate and dynamic range
/// rather than the server's `matchFrameRate`: the engine can't turn off the frame-rate
/// switch alone without losing HDR matching. Read again whenever the app comes back.
struct MatchContentRow: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = Self.read()

    var body: some View {
        Button {} label: {
            LabeledContent("Match Content") {
                Text(enabled ? String(localized: "On") : String(localized: "Off"))
            }
        }
        .accessibilityHint(Text("Set in tvOS Settings › Video and Audio › Match Content; switches the TV to each video's frame rate and dynamic range"))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { enabled = Self.read() }
        }
        .onAppear { enabled = Self.read() }
    }

    private static func read() -> Bool {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            if let window = scene.windows.first { return window.displayCriteriaMatchingEnabled }
        }
        return false
    }
}
