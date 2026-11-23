import SwiftUI

/// Watch Together on the TV details page: More › Watch Together… opens the invite picker,
/// creating a room opens its lobby (which starts the room's playback itself).
extension DetailsView {
    var watchTogetherItem: some View {
        Button { watchTogetherPicking = true } label: { Label("Watch Together…", systemImage: "person.2") }
            .disabled(title == nil)
    }

    var watchTogetherPresentation: some ViewModifier {
        DetailsWatchTogether(target: target, logoURL: title?.logo?.url, overview: overview,
                             picking: $watchTogetherPicking, openedRoom: $openedRoom)
    }
}

private struct DetailsWatchTogether: ViewModifier {
    let target: DetailsTarget
    let logoURL: String?
    let overview: String?
    @Binding var picking: Bool
    @Binding var openedRoom: WatchRoomRoute?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $picking) {
                WatchTogetherPickerView(target: target, logoURL: logoURL, overview: overview) { route in
                    picking = false
                    openedRoom = route
                }
            }
            .navigationDestination(item: $openedRoom) { WatchRoomView(route: $0).pinsSideMenu() }
    }
}
