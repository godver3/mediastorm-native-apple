import XCTest
@testable import StrmrTV

/// Customize Buttons: the defaults, per-profile choices and what can't be moved.
@MainActor
final class DetailsButtonsStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "DetailsButtonsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testManageListsAndQualityStartInMore() {
        let store = DetailsButtonsStore(defaults: defaults)
        XCTAssertEqual(store.inMore(profileID: "a"), [.lists, .quality])
        XCTAssertFalse(store.inRow(.quality, profileID: "a"))
        XCTAssertFalse(store.inRow(.lists, profileID: "a"))
        XCTAssertTrue(store.inRow(.startOver, profileID: "a"))
    }

    func testChoicesArePerProfileAndPersist() {
        let store = DetailsButtonsStore(defaults: defaults)
        store.setInRow(.trailer, false, profileID: "a")
        store.setInRow(.lists, true, profileID: "a")
        XCTAssertEqual(store.inMore(profileID: "a"), [.trailer, .quality])
        XCTAssertEqual(store.inMore(profileID: "b"), [.lists, .quality])

        let reloaded = DetailsButtonsStore(defaults: defaults)
        XCTAssertFalse(reloaded.inRow(.trailer, profileID: "a"))
        XCTAssertTrue(reloaded.inRow(.lists, profileID: "a"))
    }

    func testPlayAndMoreStayInRow() {
        let store = DetailsButtonsStore(defaults: defaults)
        store.setInRow(.primary, false, profileID: "a")
        store.setInRow(.more, false, profileID: "a")
        XCTAssertTrue(store.inRow(.primary, profileID: "a"))
        XCTAssertTrue(store.inRow(.more, profileID: "a"))
    }

    func testQualityMovesToRowAndBack() {
        let store = DetailsButtonsStore(defaults: defaults)
        store.setInRow(.quality, true, profileID: "a")
        XCTAssertTrue(DetailsButtonsStore(defaults: defaults).inRow(.quality, profileID: "a"))
        store.setInRow(.quality, false, profileID: "a")
        XCTAssertFalse(DetailsButtonsStore(defaults: defaults).inRow(.quality, profileID: "a"))
    }

    /// A profile that customized its buttons before Quality existed gets it in More.
    func testQualityStartsInMoreForLegacyChoices() {
        defaults.set(["a": ["trailer"]], forKey: DetailsButtonsStore.Keys.inMore)
        let store = DetailsButtonsStore(defaults: defaults)
        XCTAssertEqual(store.inMore(profileID: "a"), [.trailer, .quality])
        XCTAssertTrue(store.inRow(.lists, profileID: "a"))
    }
}
