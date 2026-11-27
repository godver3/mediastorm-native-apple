import AetherEngine
import AVKit
import Combine
import UIKit

/// What every player shares: AVPlayerViewController over AetherEngine, the software (dav1d / VP9)
/// route's own surface, the overlay every subtitle is drawn in, and on tvOS the app's own
/// transport (`SoftwareTransportHUD`, `+Transport`) in place of AVKit's bar on both routes, so
/// VOD, live, catch-up and recordings share one layout and differ only in their buttons.
/// The engine owns demux/decode; AVKit only sees the engine's AVPlayer.
class EnginePlayerViewController: AVPlayerViewController {
    let engine: AetherEngine
    let log: AppLog
    var cancellables = Set<AnyCancellable>()
    let settingsHider = TransportSettingsHider()
    let subtitleOverlay = SubtitleOverlayView()
    let softwareSurface = AetherPlayerView()
    /// The time of day while AVKit's transport bar is up (`+Clock`); the software route's HUD
    /// has its own.
    let clockLabel = PlayerClockLabel()
    private(set) var softwareSurfaceMounted = false
    /// The player's controls (AVKit's transport bar, or the software route's HUD) came up or
    /// went away; the VOD player shows its watch-room presence with them.
    func controlsVisibilityChanged(_ visible: Bool) {}
    /// The display's Match Content setting, read when the player appears.
    var matchContent = false
    /// The info panel's artwork load (`+InfoPanel`); internal for that file.
    var infoArtworkTask: Task<Void, Never>?
    /// The Stream info tab and its session-fixed rows (`+StreamInfo`); internal for that file.
    lazy var streamInfoTab = StreamInfoViewController()
    var streamInfoBase = StreamInfo()
    /// This stream's audio offset in ms (`+AudioOffset`), loaded from `AudioOffsetStore` under
    /// `audioOffsetKey`. Every load this player makes (Switch Source, audio-track reload) replays it.
    var audioOffsetMs = 0
    /// The stream's `AudioOffsetStore` key; set by each player before its first load.
    var audioOffsetKey: String? {
        didSet {
            guard audioOffsetKey != oldValue else { return }
            audioOffsetTask?.cancel()
            audioOffsetMs = audioOffsetKey.map { AudioOffsetStore.shared.offset(for: $0) } ?? 0
        }
    }
    /// The debounced `setAudioDelay` after Audio Offset presses (`+AudioOffset`).
    var audioOffsetTask: Task<Void, Never>?

    init(engine: AetherEngine, logCategory: String) {
        self.engine = engine
        log = AppLog(category: logCategory)
        super.init(nibName: nil, bundle: nil)
        // Over, not full screen: .fullScreen removes the SwiftUI hierarchy underneath while the
        // player is up, and it came back rebuilt (navigation popped to Home) on dismissal.
        modalPresentationStyle = .overFullScreen
        // Fades in over the loading art rather than sliding up from below it.
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        showsPlaybackControls = !ownsTransport
        // The engine is the sole display-criteria writer (HDR / DV / frame-rate match);
        // AVKit's automatic criteria would race it.
        appliesPreferredDisplayCriteriaAutomatically = false
        allowsPictureInPicturePlayback = false
        #if os(tvOS)
        let menu = UITapGestureRecognizer(target: self, action: #selector(softwareMenuPressed))
        menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        menu.delegate = self
        view.addGestureRecognizer(menu)
        installClock()
        #endif
        // iOS has no Menu button, and with its default touch types this recognizer took the
        // taps on the video that bring AVKit's controls back once they have hidden.
        #if os(iOS)
        installTouchClose()
        observeVideoSize()
        #endif

        // Native path: hand AVKit the engine's AVPlayer. nil on the software route, which
        // renders into `softwareSurface` instead.
        engine.$currentAVPlayer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] avPlayer in self?.player = avPlayer }
            .store(in: &cancellables)
    }

    #if os(iOS)
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { Self.playerOrientations }

    /// The player draws its own touch transport on the software route (the VOD player's
    /// `MobilePlayerControls`), so the base class's close button stays hidden.
    var hasTouchTransport: Bool { false }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enterPreferredOrientation()
    }
    #endif

    /// `finish()` logs the close only once the dismissal has finished; this marks its start, so
    /// a crash during the transition is told apart from one during playback.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed { log.notice("player dismissing") }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        #if os(iOS)
        Self.restorePortrait()
        #endif
        finish()
    }

    /// The Stream tab's rows changed (`+StreamInfo`); the software route's HUD shows the summary.
    func streamInfoDidChange(_ info: StreamInfo) {}

    /// The app's own transport replaces AVKit's bar: always on tvOS (one layout for every kind of
    /// playback, on both routes), on iOS only on the software route, where AVKit has no AVPlayer.
    var ownsTransport: Bool {
        #if os(tvOS)
        true
        #else
        softwareSurfaceMounted
        #endif
    }

    /// The player's HUD while it owns the transport (tvOS); nil for none.
    var transportHUD: SoftwareTransportHUD? { nil }

    /// Whether the app's HUD has something Menu should close (the Skip capsule, the row, the
    /// Info card, then the bar) before the player, as AVKit's bar does.
    @objc dynamic var softwareHUDHasOpenLayer: Bool {
        guard ownsTransport, let hud = transportHUD, hud.superview != nil else { return false }
        return hud.isActionFocused || hud.rowFocused || hud.isInfoShowing || hud.isShowing
    }

    /// Closes the HUD's topmost open layer; called for a Menu press while there is one.
    @objc dynamic func closeSoftwareHUDLayer() {
        guard let hud = transportHUD else { return }
        if hud.rowFocused || hud.isInfoShowing {
            hud.releaseRow()
            hud.setInfo(visible: false)
        } else {
            hud.hide()
        }
    }

    #if os(tvOS)
    /// The HUD takes focus for its row and Skip capsule.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if ownsTransport, let hud = transportHUD, hud.superview != nil, hud.wantsFocus { return [hud] }
        return super.preferredFocusEnvironments
    }

    /// A menu closed from the HUD's row hands focus to AVKit's container rather than back to the
    /// button it opened from; while the HUD wants focus, take it back, as AVKit's own bar does.
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard ownsTransport, let hud = transportHUD, hud.wantsFocus, let next = context.nextFocusedView,
              next.isDescendant(of: view), !next.isDescendant(of: hud) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
    }
    #endif

    /// UIKit closes a presented player on Menu with its own gesture, which no press handler can
    /// veto; this recognizer takes the press instead while the HUD has something open.
    @objc private func softwareMenuPressed() {
        closeSoftwareHUDLayer()
    }

    /// Tears the session down once the player has been dismissed. Subclasses override it.
    func finish() {}

    /// Where overlays go: AVKit's content overlay, above the video.
    var overlayHost: UIView { contentOverlayView ?? view! }

    /// Sizes `subview` to `host` and keeps it that way.
    static func fill(_ subview: UIView, in host: UIView) {
        subview.frame = host.bounds
        subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    /// Mounts (or removes) the software route's surface at the bottom of the overlay host and
    /// binds the engine to it. AVKit has no AVPlayer to drive on that route, so its chrome
    /// would only show an idle spinner; it is hidden and the remote is handled in
    /// `pressesBegan`. Returns false when nothing changed.
    @discardableResult
    func mountSoftwareSurface(_ mounted: Bool) -> Bool {
        guard mounted != softwareSurfaceMounted else { return false }
        if mounted {
            Self.fill(softwareSurface, in: overlayHost)
            overlayHost.insertSubview(softwareSurface, at: 0)
            engine.bind(view: softwareSurface)
        } else {
            engine.unbind(view: softwareSurface)
            softwareSurface.removeFromSuperview()
        }
        softwareSurfaceMounted = mounted
        if mounted { clockLabel.alpha = 0 }
        showsPlaybackControls = !ownsTransport
        #if os(iOS)
        updateTouchClose(softwareMounted: mounted)
        #endif
        return true
    }

    /// Options every session starts from; callers add their own.
    func baseLoadOptions() -> LoadOptions {
        var options = LoadOptions()
        options.httpHeaders = APIClient.shared.mediaHeaders
        options.matchContentEnabled = matchContent
        // Fallback when the backend expresses no audio preference; an explicit stream index
        // (the profile's resolved pick) wins over this.
        options.preferredAudioLanguages = TrackPreferences.deviceLanguages
        // Every subtitle is drawn by `SubtitleOverlayView` (AetherEngine's fullscreen design), so
        // no native renditions: AVKit selecting one stalled playback on a bitmap track's empty
        // OCR rendition, and building them costs a second source read.
        options.prepareNativeSubtitles = false
        // This stream's lip-sync offset from the Audio Offset menu (0 until changed).
        options.audioDelaySeconds = AudioOffset.seconds(audioOffsetMs)
        return options
    }
}

#if os(tvOS)
// tvOS only: AVPlayerViewController is the delegate of AVKit's own gesture recognizers, and on iOS
// a subclass `gestureRecognizerShouldBegin` overrides AVKit's, so every tap on the video failed to
// begin and AVKit's controls never came back once hidden. iOS has no Menu recognizer to serve.
extension EnginePlayerViewController: UIGestureRecognizerDelegate {
    /// The Menu recognizer only takes presses that close part of the app's HUD.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        softwareHUDHasOpenLayer
    }
}
#endif
