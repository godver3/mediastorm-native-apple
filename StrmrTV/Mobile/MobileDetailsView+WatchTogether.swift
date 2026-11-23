#if os(iOS)
import SwiftUI

/// Watch Together on the phone details page: More › Watch Together… opens the invite sheet,
/// creating a room opens its lobby (which starts the room's playback itself).
struct MobileDetailsWatchTogether: ViewModifier {
    @ObservedObject var model: MobileDetailsModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.watchTogetherPicking) {
                MobileWatchTogetherPicker(target: model.target, logoURL: model.title?.logo?.url,
                                          overview: model.overview) { route in
                    model.watchTogetherPicking = false
                    model.openedRoom = route
                }
            }
            .navigationDestination(item: $model.openedRoom) { MobileWatchRoomView(route: $0) }
    }
}
#endif
