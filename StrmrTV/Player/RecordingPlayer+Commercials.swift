import UIKit

/// A finished recording's commercial breaks (comskip): Skip Commercial while one plays, or a
/// jump over it by itself when the profile has commercial auto-skip on.
@MainActor
final class CommercialBreaks {
    var breaks: [SkipSegment] = []
    var requested = false
    var autoSkip = false
    /// The break Skip Commercial is offered for.
    var active: SkipSegment?
    /// Menu over the button: not offered again for this break.
    var dismissed: SkipSegment?
    /// Breaks jumped over by themselves: once each, so seeking back into one plays it.
    var autoSkipped = Set<SkipSegment>()
    /// The break a skip is seeking past: no button for it until playback has left it.
    var skipping: SkipSegment?
}

extension RecordingPlayerViewController {
    /// Asks the server for the breaks once (`POST /api/video/segments` with the recording's ID).
    /// A growing recording has none yet: the server marks them once it is done.
    func loadCommercials() {
        let state = commercialBreaks
        guard !growing, !state.requested else { return }
        state.requested = true
        var body: [String: Any] = ["recordingId": recording.id]
        if engine.duration > 0 { body["duration"] = engine.duration }
        Task { [weak self] in
            // A failed request is tried twice more.
            var found: [SkipSegment] = []
            for attempt in 0..<3 {
                if attempt > 0 { try? await Task.sleep(for: .seconds(10)) }
                guard self?.didFinish == false else { return }
                if let answer = try? await APIClient.shared.skipSegments(body) {
                    found = answer
                    break
                }
            }
            let skip = found.contains { $0.type == "commercial" } ? await PlaybackCoordinator.shared.commercialAutoSkip() : false
            guard let self, !didFinish else { return }
            state.breaks = found.filter { $0.type == "commercial" && $0.end > $0.start }.sorted { $0.start < $1.start }
            state.autoSkip = skip
            if !state.breaks.isEmpty {
                log.info("\(state.breaks.count) commercial breaks, auto-skip \(skip)")
            }
        }
    }

    /// Inside a break: jump over it (auto-skip, once per break) or offer Skip Commercial.
    func updateCommercial(at time: Double) {
        let state = commercialBreaks
        guard !state.breaks.isEmpty, scrubTarget == nil else { return }
        let found = state.breaks.first { time >= $0.start && time < $0.end - 1 }
        if let skipping = state.skipping {
            if found == skipping { return } // the seek past it has not landed yet
            state.skipping = nil
        }
        if let found, state.autoSkip, state.autoSkipped.insert(found).inserted {
            log.notice("skipping commercial \(Int(found.start))-\(Int(found.end))s")
            skipCommercial(found)
            return
        }
        let segment = found == state.dismissed ? nil : found
        guard segment != state.active else { return }
        state.active = segment
        setCommercialAction(segment.map { segment in
            UIAction(title: String(localized: "Skip Commercial"), image: UIImage(systemName: "forward.fill")) { [weak self] _ in
                self?.skipCommercial(segment)
            }
        })
    }

    func skipCommercial(_ segment: SkipSegment) {
        let end = transportDuration > 0 ? min(segment.end, transportDuration) : segment.end
        commercialBreaks.active = nil
        commercialBreaks.skipping = segment
        setCommercialAction(nil)
        Task { await seekPlayback(to: end) }
    }

    /// The button: AVKit's contextual action, and the phone's controls or the TV's HUD where
    /// they own the transport.
    func setCommercialAction(_ action: UIAction?) {
        let hadAction = !contextualActions.isEmpty
        contextualActions = action.map { [$0] } ?? []
        #if os(iOS)
        mobileControls.setAction(action)
        #else
        softwareHUD.setAction(action)
        #endif
        // Removing the button while it holds focus left AVKit with nothing focused; on the TV's
        // HUD the new button takes focus (preferredFocusEnvironments), so Select presses it,
        // unless the menu row or the Info card is in use.
        #if os(tvOS)
        let takeFocus = action != nil && ownsTransport && !softwareHUD.rowFocused && !softwareHUD.isInfoShowing
        #else
        let takeFocus = false
        #endif
        if (hadAction && action == nil) || takeFocus {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }

    /// Menu over Skip Commercial: drop it for this break (AVKit's remote handling stays stuck
    /// while a contextual action is set).
    func dismissCommercialAction() -> Bool {
        guard let active = commercialBreaks.active, !contextualActions.isEmpty else { return false }
        commercialBreaks.dismissed = active
        commercialBreaks.active = nil
        setCommercialAction(nil)
        return true
    }
}
