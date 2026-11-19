import Foundation

/// Complete passes in flight across every Home view: each can take a while on a cold
/// server and holds a connection, so only a few run at once.
@MainActor
enum CompletionGate {
    private static let limit = 4
    private static var running = 0
    private static var waiting: [CheckedContinuation<Void, Never>] = []

    static func run<T>(_ work: () async throws -> T) async rethrows -> T {
        if running < limit { running += 1 } else { await withCheckedContinuation { waiting.append($0) } }
        // A finished pass hands its slot straight to the next waiting one.
        defer { if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() } }
        return try await work()
    }
}
