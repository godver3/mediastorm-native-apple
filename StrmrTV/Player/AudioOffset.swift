import Foundation

/// The audio presentation offset (lip-sync delay) as the menus and Settings spell it: whole
/// milliseconds, positive meaning audio is delayed (AetherEngine `audioDelaySeconds`). Remembered
/// per stream (`AudioOffsetStore`); there is no global default.
enum AudioOffset {
    /// One press of Later / Earlier.
    static let stepMs = 50
    /// The engine's own bound (`AudioDelayPolicy.maxAbsSeconds`, 2 s), which it doesn't export.
    static let maxAbsMs = 2000
    /// Quiet time after the last press before the value reaches the engine (one reload per burst).
    static let settleMs = 1500

    /// Into range and onto the step grid.
    static func clamp(_ ms: Int) -> Int {
        let bounded = min(max(ms, -maxAbsMs), maxAbsMs)
        return Int((Double(bounded) / Double(stepMs)).rounded()) * stepMs
    }

    /// "0 ms", "+150 ms", "−100 ms" (a true minus sign).
    static func label(_ ms: Int) -> String {
        if ms == 0 { return "0 ms" }
        return "\(ms > 0 ? "+" : "\u{2212}")\(abs(ms)) ms"
    }

    static func seconds(_ ms: Int) -> Double { Double(ms) / 1000 }

}

/// Each stream's remembered offset, keyed by what the stream is rather than where it comes from
/// (so a source switch or a retune keeps it). One UserDefaults dictionary, newest last, capped.
///
/// Keys (`AudioOffsetStore.Key`):
/// - live and catch-up: `live:<channel id>` (catch-up shares its channel's value)
/// - VOD: `vod:<id>`, the id progress reports under: the movie's title ID, the episode's server
///   itemId, else `<series title ID>:SxxEyy`
/// - recordings: `rec:<recording id>`
@MainActor
final class AudioOffsetStore {
    static let shared = AudioOffsetStore()
    static let defaultsKey = "strmrtv.audioOffsets"
    static let orderKey = "strmrtv.audioOffsetsOrder"
    static let maxEntries = 500

    enum Key {
        static func live(_ channelID: String) -> String { "live:\(channelID)" }
        static func vod(_ itemID: String) -> String { "vod:\(itemID)" }
        static func recording(_ id: String) -> String { "rec:\(id)" }
    }

    private let defaults: UserDefaults
    private let cap: Int

    init(defaults: UserDefaults = .standard, cap: Int = AudioOffsetStore.maxEntries) {
        self.defaults = defaults
        self.cap = cap
    }

    private var values: [String: Int] { (defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int]) ?? [:] }
    private var order: [String] { defaults.stringArray(forKey: Self.orderKey) ?? [] }

    /// The stream's offset, 0 when none is remembered.
    func offset(for key: String) -> Int { AudioOffset.clamp(values[key] ?? 0) }

    /// Remembers `ms` for the stream (most recent); 0 forgets it. The oldest entries go past the cap.
    func set(_ ms: Int, for key: String) {
        var values = values
        var order = order.filter { $0 != key && values[$0] != nil }
        let clamped = AudioOffset.clamp(ms)
        if clamped == 0 {
            values[key] = nil
        } else {
            values[key] = clamped
            order.append(key)
        }
        while order.count > cap { values[order.removeFirst()] = nil }
        defaults.set(values, forKey: Self.defaultsKey)
        defaults.set(order, forKey: Self.orderKey)
    }

    var count: Int { values.count }
}

extension PlaybackRequest {
    /// This title's `AudioOffsetStore` key: the id progress reports under.
    var audioOffsetKey: String {
        guard let episode else { return AudioOffsetStore.Key.vod(title.titleID) }
        return AudioOffsetStore.Key.vod(episode.itemID ?? "\(title.titleID):\(episode.code)")
    }
}
