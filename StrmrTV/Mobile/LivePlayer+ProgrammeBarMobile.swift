#if os(iOS)
import AetherEngine
import UIKit

/// The programme bar on a phone or iPad: a channel with provider catch-up draws the TV's
/// `SoftwareTransportHUD` there, which only the Siri Remote can bring back once it fades, and
/// which has no close button. So the phone's own controls (`MobilePlayerControls`) are the whole
/// transport instead, as on a growing recording: tap shows and hides them, ✕ closes the player,
/// the scrubber spans the programme at the playhead, ±10 s and a lifted scrub go where
/// `seekProgramme` decides (in place, the archive or live), and a badge says LIVE or how far
/// behind. Start Over and Go Live sit in a menu with Add Screen; Subtitles and Cast keep their
/// own buttons.
extension LivePlayerViewController {
    func installMobileProgrammeBar() {
        let controls = mobileControls
        Self.fill(controls, in: view)
        view.addSubview(controls)
        controls.onClose = { [weak self] in self?.dismiss(animated: true) }
        controls.onPlayPause = { [weak self] in
            guard let self, pausable else { return }
            engine.togglePlayPause()
        }
        controls.onSkip = { [weak self] delta in
            guard let self else { return }
            seekProgramme(to: min(Date(), catchupPlayhead.addingTimeInterval(delta)))
        }
        controls.onScrub = { [weak self] time, ended in self?.mobileProgrammeScrub(to: time, ended: ended) }
        controls.setCastAction { [weak self] in self?.openCastPicker() }
        controls.setOwnsTransport(true)
        refreshMobileProgrammeRow()
    }

    /// The bar, the title and the LIVE / behind badge, from the programme at the playhead.
    func refreshMobileProgrammeBar() {
        let transport = mobileControls.transport
        let paused = if case .paused = engine.state { true } else { false }
        let playhead = catchupPlayhead
        let behind = max(0, Date().timeIntervalSince(playhead))
        transport.setBadge(behind > LiveTimeshiftStatusView.atLiveSeconds
            ? "-" + SoftwareTransportHUD.clock(behind) : String(localized: "LIVE"))
        guard let program = LiveCatchupRules.program(at: playhead, in: catchupPrograms) else {
            transport.setTitle(channel.name, subtitle: nil)
            transport.scrubLimit = 0
            mobileControls.update(position: 0, duration: 0, paused: paused)
            return
        }
        transport.setTitle(program.title, subtitle: channel.name)
        // Nothing past now has aired: the drag stops at live (tvOS and Android clamp the same way).
        transport.scrubLimit = max(0, Date().timeIntervalSince(program.start))
        mobileControls.update(position: playhead.timeIntervalSince(program.start),
                              duration: max(1, program.stop.timeIntervalSince(program.start)), paused: paused)
    }

    /// Start Over, Go Live and Add Screen in one menu, then the Subtitles menu when there is one.
    /// Cast has its own button (`setCastAction`), so it is left out of the shared items here.
    func refreshMobileProgrammeRow() {
        let startOver = UIAction(title: String(localized: "Start Over"), image: UIImage(systemName: "gobackward")) {
            [weak self] _ in self?.startOver()
        }
        let goLive = UIAction(title: String(localized: "Go Live"), image: UIImage(systemName: "forward.end")) {
            [weak self] _ in self?.programmeGoLive()
        }
        let castTitle = String(localized: "Cast")
        let shared = transportBarCustomMenuItems.filter { !($0 is UIAction && $0.title == castTitle) }
        let actions = shared.filter { !($0 is UIMenu) }
        let menus = shared.compactMap { $0 as? UIMenu }
        let programme = UIMenu(title: "", image: UIImage(systemName: "ellipsis"), children: [startOver, goLive] + actions)
        programme.accessibilityLabel = String(localized: "Options")
        mobileControls.setMenus([programme] + menus)
    }

    /// The scrubber moved: the time follows the finger; lifting it goes there in the programme.
    private func mobileProgrammeScrub(to time: Double, ended: Bool) {
        mobileControls.transport.showPreview(time: time, image: nil, hasThumbnails: false)
        guard ended else { return }
        mobileControls.transport.hidePreview()
        guard let program = LiveCatchupRules.program(at: catchupPlayhead, in: catchupPrograms) else { return }
        let target = min(Date(), program.start.addingTimeInterval(time))
        log.info("programme bar: touch scrub to \(Int(time))s into \(program.title)")
        seekProgramme(to: target)
    }
}
#endif
