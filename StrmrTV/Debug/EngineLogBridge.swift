import AetherEngine
import Foundation

/// Mirrors AetherEngine's diagnostic lines into the app log under `[engine]`, so a submitted log
/// shows what the engine did (a live re-cut, an audio timestamp gap, an output change) and not
/// only what the player saw. The engine hands over its info lines with credentials already
/// stripped; its per-segment trace stays in OSLog, and the loopback server's line per request is
/// left out (a live session makes several a segment, and they would push the rest out of the
/// 4 MB file). A burst is capped at `limit` lines per `window`, and the count dropped is logged
/// when the next window opens.
enum EngineLogBridge {
    private static let limit = 60
    private static let window: TimeInterval = 10
    private static let log = AppLog(category: "engine")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var windowStart = Date.distantPast
    nonisolated(unsafe) private static var lines = 0
    nonisolated(unsafe) private static var dropped = 0

    static func install() {
        EngineLog.handler = { line in
            guard !line.hasPrefix("[HLSLocalServer] GET "), !isTrickPlayNoise(line) else { return }
            if isAlwaysKept(line) {
                log.info(line)
                return
            }
            let (pass, droppedBefore) = admit()
            if droppedBefore > 0 { log.info("(\(droppedBefore) engine lines dropped)") }
            if pass { log.info(line) }
        }
    }

    /// Scrubbing-thumbnail misses: a reload fires dozens at once and they used to spend the whole
    /// window's budget, dropping the gate lines that show the reload's A/V offset.
    private static func isTrickPlayNoise(_ line: String) -> Bool {
        line.hasPrefix("[HLSLocalServer] -> 404 /iframe")
            || (line.hasPrefix("[HLSLocalServer] send failed for /iframe"))
    }

    /// A/V-sync evidence, a few lines per load or restart, so it bypasses the cap.
    private static func isAlwaysKept(_ line: String) -> Bool {
        line.hasPrefix("[HLSSegmentProducer] video gate open")
            || line.hasPrefix("[HLSSegmentProducer] audio gate open")
            || line.hasPrefix("[HLSSegmentProducer] WARNING: audio gate")
            || line.hasPrefix("[HLSSegmentProducer] init OK")
            || line.hasPrefix("[HLSVideoEngine] audio:")
            || line.hasPrefix("[HLSVideoEngine] initial producer anchored")
            || line.hasPrefix("[NativeAVPlayerHost]") && line.contains(" load url=")
            || line.hasPrefix("[AetherEngine] reload")
    }

    /// Whether this line fits the current window, and how many the previous window dropped.
    private static func admit() -> (Bool, Int) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        var droppedBefore = 0
        if now.timeIntervalSince(windowStart) >= window {
            droppedBefore = dropped
            windowStart = now
            lines = 0
            dropped = 0
        }
        guard lines < limit else {
            dropped += 1
            return (false, droppedBefore)
        }
        lines += 1
        return (true, droppedBefore)
    }
}
