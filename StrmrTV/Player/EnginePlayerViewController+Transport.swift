import UIKit

/// The one transport every tvOS player shows (`SoftwareTransportHUD`, laid out as AVKit's bar),
/// on both routes: what differs between VOD, live, catch-up and recordings is only the buttons
/// in its row and what Left / Right / Select do. Up and Down move between the bar, the row and
/// the Info card the same way everywhere (`handleTransportNavigation`).
extension EnginePlayerViewController {
    /// Adds the HUD over the player (below `cover`, a loading cover, when given) and wires its
    /// focus requests. Idempotent.
    func installTransportHUD(_ hud: SoftwareTransportHUD, below cover: UIView? = nil) {
        guard hud.superview == nil else { return }
        hud.onFocusChange = { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
        // The Stream tab: AVKit's custom info tab, now a tab of the HUD's panel.
        if streamInfoTab.parent == nil {
            addChild(streamInfoTab)
            hud.setStreamView(streamInfoTab.view)
            streamInfoTab.didMove(toParent: self)
        }
        Self.fill(hud, in: view)
        if let cover, cover.superview === view {
            view.insertSubview(hud, belowSubview: cover)
        } else {
            view.addSubview(hud)
        }
    }

    /// Up / Down, as AVKit's bar: Up closes the Info panel, else focuses the row (bar up), else
    /// shows the bar; Down leaves the row, else opens or closes the panel. Left / Right while the
    /// panel is open switch its tab (Info, Stream). False for any other press.
    func handleTransportNavigation(_ type: UIPress.PressType) -> Bool {
        guard let hud = transportHUD else { return false }
        switch type {
        case .upArrow:
            if hud.isInfoShowing {
                hud.setInfo(visible: false)
            } else if hud.isShowing, !hud.rowFocused, hud.hasMenus {
                hud.focusRow()
            } else {
                hud.flash()
            }
        case .downArrow:
            if hud.rowFocused {
                hud.releaseRow()
                hud.flash()
            } else {
                hud.setInfo(visible: !hud.isInfoShowing)
            }
        case .leftArrow, .rightArrow:
            guard hud.isInfoShowing, !hud.rowFocused else { return false }
            _ = hud.stepInfoTab(forward: type == .rightArrow)
            hud.flash()
        default:
            return false
        }
        return true
    }
}
