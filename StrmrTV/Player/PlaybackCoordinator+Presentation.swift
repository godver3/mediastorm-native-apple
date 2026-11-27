import UIKit

/// What is on screen: whether a player is up, for screens and background work.
extension PlaybackCoordinator {
    /// The full-screen player is up (nothing SwiftUI can present over it).
    var isPresentingPlayer: Bool {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let current = vc {
            if current is PlayerViewController { return true }
            vc = current.presentedViewController
        }
        return false
    }

    /// A stream is resolving or a player (VOD or live) is up: no background speed tests.
    var isBusy: Bool {
        resolving != nil || Self.topViewController().map { top in
            var vc: UIViewController? = top
            while let current = vc {
                if current is EnginePlayerViewController { return true }
                vc = current.presentingViewController
            }
            return false
        } ?? false
    }
}
