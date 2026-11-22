import AetherEngine
import UIKit

/// The players' Audio Offset menu: Later / Earlier by 50 ms and Reset, titled with the value in
/// force. The value is saved under the stream's key (`AudioOffsetStore`; 0 forgets it) and reaches the engine after
/// presses settle, since each `setAudioDelay` on the loopback route replaces the player item (a
/// live reload). Later / Earlier keep the menu open so several presses add up to one commit.
extension EnginePlayerViewController {
    /// `onChange` rebuilds the menus that carry this one so the title shows the new value.
    func audioOffsetMenu(onChange: @escaping @MainActor () -> Void) -> UIMenu {
        let current = audioOffsetMs
        let later = UIAction(title: String(localized: "Later (+\(AudioOffset.stepMs) ms)"),
                             image: UIImage(systemName: "plus"), attributes: .keepsMenuPresented) { [weak self] _ in
            guard let self else { return }
            nudgeAudioOffset(to: audioOffsetMs + AudioOffset.stepMs, onChange: onChange)
        }
        let earlier = UIAction(title: String(localized: "Earlier (\u{2212}\(AudioOffset.stepMs) ms)"),
                               image: UIImage(systemName: "minus"), attributes: .keepsMenuPresented) { [weak self] _ in
            guard let self else { return }
            nudgeAudioOffset(to: audioOffsetMs - AudioOffset.stepMs, onChange: onChange)
        }
        let reset = UIAction(title: String(localized: "Reset"), image: UIImage(systemName: "arrow.counterclockwise"),
                             attributes: current == 0 ? .disabled : []) { [weak self] _ in
            self?.nudgeAudioOffset(to: 0, onChange: onChange)
        }
        let title = String(localized: "Audio Offset: \(AudioOffset.label(current))")
        return UIMenu(title: title, image: UIImage(systemName: "waveform.badge.plus"), children: [later, earlier, reset])
    }

    private func nudgeAudioOffset(to ms: Int, onChange: @escaping @MainActor () -> Void) {
        audioOffsetMs = AudioOffset.clamp(ms)
        if let audioOffsetKey { AudioOffsetStore.shared.set(audioOffsetMs, for: audioOffsetKey) }
        log.notice("audio offset menu pick: \(AudioOffset.label(self.audioOffsetMs))")
        onChange()
        audioOffsetTask?.cancel()
        audioOffsetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(AudioOffset.settleMs))
            guard let self, !Task.isCancelled else { return }
            engine.setAudioDelay(AudioOffset.seconds(audioOffsetMs))
        }
    }
}
