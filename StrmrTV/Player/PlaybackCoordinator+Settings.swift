import Foundation

/// The profile's and the server's playback settings, cached for the coordinator and the players.
extension PlaybackCoordinator {
    /// The admin's preview-thumbnail switch, re-read at most every five minutes.
    func previewThumbnailsEnabled() async -> Bool {
        if let previewSetting, Date().timeIntervalSince(previewSetting.fetched) < 300 { return previewSetting.enabled }
        let enabled = await api.previewThumbnailsEnabled()
        previewSetting = (enabled, Date())
        return enabled
    }

    /// The profile's credits auto-skip, and the server's on-device credits detection switch.
    func creditsSettings() async -> (autoSkip: Bool, detection: Bool) {
        let settings = await playbackSettings()
        return (settings.creditsAutoSkip, settings.creditsDetectionEnabled)
    }

    /// The profile's commercial auto-skip, for recordings.
    func commercialAutoSkip() async -> Bool {
        await playbackSettings().commercialAutoSkip
    }

    /// The profile's playback settings, re-read at most every five minutes (or on a profile switch).
    func playbackSettings() async -> APIClient.PlaybackSettings {
        let profile = api.profileID
        if let settings, settings.profile == profile,
           Date().timeIntervalSince(settings.fetched) < 300 { return settings.value }
        let value = await api.playbackSettings()
        settings = (value, profile, Date())
        SubtitleStyleStore.shared.adopt(value.subtitleStyle)
        return value
    }

    /// Reads the server's subtitle style now, so Settings shows the current one (playback
    /// reads it with the rest of the profile's settings).
    func refreshSubtitleStyle() async {
        settings = nil
        _ = await playbackSettings()
    }
}
