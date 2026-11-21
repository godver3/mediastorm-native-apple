import XCTest
@testable import StrmrTV

@MainActor
final class AudioOffsetTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(AudioOffset.label(0), "0 ms")
        XCTAssertEqual(AudioOffset.label(150), "+150 ms")
        XCTAssertEqual(AudioOffset.label(-100), "\u{2212}100 ms")
    }

    func testClampBoundsAndSnapsToStep() {
        XCTAssertEqual(AudioOffset.clamp(5000), 2000)
        XCTAssertEqual(AudioOffset.clamp(-5000), -2000)
        XCTAssertEqual(AudioOffset.clamp(74), 50)
        XCTAssertEqual(AudioOffset.clamp(-80), -100)
        XCTAssertEqual(AudioOffset.seconds(150), 0.15, accuracy: 1e-9)
    }

    func testClampKeepsInRangeStepsAndZero() {
        XCTAssertEqual(AudioOffset.clamp(0), 0)
        XCTAssertEqual(AudioOffset.clamp(-150), -150)
        XCTAssertEqual(AudioOffset.clamp(2000), 2000)
        XCTAssertEqual(AudioOffset.seconds(-100), -0.1, accuracy: 1e-9)
    }

    private func makeStore(cap: Int = AudioOffsetStore.maxEntries) throws -> (AudioOffsetStore, UserDefaults, String) {
        let suite = "AudioOffsetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (AudioOffsetStore(defaults: defaults, cap: cap), defaults, suite)
    }

    func testKeys() {
        XCTAssertEqual(AudioOffsetStore.Key.live("abc"), "live:abc")
        XCTAssertEqual(AudioOffsetStore.Key.vod("tmdb:movie:1"), "vod:tmdb:movie:1")
        XCTAssertEqual(AudioOffsetStore.Key.recording("r1"), "rec:r1")
    }

    func testRemembersPerKeyAndAcrossInstances() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(store.offset(for: "live:a"), 0)
        store.set(150, for: "live:a")
        store.set(-100, for: "vod:m")
        XCTAssertEqual(AudioOffsetStore(defaults: defaults).offset(for: "live:a"), 150)
        XCTAssertEqual(AudioOffsetStore(defaults: defaults).offset(for: "vod:m"), -100)
        XCTAssertEqual(store.offset(for: "live:b"), 0)
        store.set(9999, for: "rec:1")
        XCTAssertEqual(store.offset(for: "rec:1"), 2000)
    }

    func testResetRemovesEntry() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.set(50, for: "live:a")
        store.set(0, for: "live:a")
        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(store.offset(for: "live:a"), 0)
    }

    func testCapDropsOldest() throws {
        let (store, defaults, suite) = try makeStore(cap: 3)
        defer { defaults.removePersistentDomain(forName: suite) }
        for (i, key) in ["a", "b", "c"].enumerated() { store.set(50 * (i + 1), for: key) }
        store.set(200, for: "a") // touching "a" makes "b" the oldest
        store.set(250, for: "d")
        XCTAssertEqual(store.count, 3)
        XCTAssertEqual(store.offset(for: "b"), 0)
        XCTAssertEqual(store.offset(for: "a"), 200)
        XCTAssertEqual(store.offset(for: "c"), 150)
        XCTAssertEqual(store.offset(for: "d"), 250)
    }
}
