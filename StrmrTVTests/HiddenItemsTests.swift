import XCTest
@testable import StrmrTV

/// Settings › Hidden Items: the Continue Watching hidden list decodes into the profile's
/// `HiddenItem` (plus a `hiddenAt` it ignores), rows fall back when metadata is missing,
/// and focus moves to the right neighbour when a row leaves.
final class HiddenItemsTests: XCTestCase {
    private func decode(_ json: String) throws -> [HiddenItem] {
        try JSONDecoder().decode(LossyArray<HiddenItem>.self, from: Data(json.utf8)).elements
    }

    func testContinueHiddenResponseDecodes() throws {
        let items = try decode("""
        [{"id":"tmdb:tv:30778","mediaType":"series","name":"Dinosaur Train","year":2009,
          "posterUrl":"https://example.com/p.jpg","externalIds":{"tmdb":"30778","tvdb":"116291"},
          "hiddenAt":"2026-11-19T07:41:53.679274Z"},
         {"id":"tmdb:movie:1","mediaType":"movie","hiddenAt":"2026-11-19T07:41:53Z"}]
        """)
        XCTAssertEqual(items.map(\.id), ["tmdb:tv:30778", "tmdb:movie:1"])
        XCTAssertEqual(items[0].year, 2009)
        XCTAssertEqual(items[0].externalIds?["tvdb"], "116291")
        XCTAssertTrue(items[1].isMovie)
        XCTAssertTrue(try decode("null").isEmpty)
    }

    func testDisplayFallsBackWithoutMetadata() throws {
        let items = try decode("""
        [{"id":"tmdb:tv:30778","mediaType":"series","name":"Dinosaur Train","year":2009},
         {"id":"tmdb:movie:1","mediaType":"movie","name":"  "}]
        """)
        XCTAssertEqual(items[0].displayName, "Dinosaur Train")
        XCTAssertEqual(items[0].displayDetail, "2009 · Series")
        XCTAssertEqual(items[1].displayName, "Unknown title")
        XCTAssertEqual(items[1].displayDetail, "Movie · tmdb:movie:1")
    }

    @MainActor
    func testNeighbourPrefersNextThenPrevious() throws {
        let items = try decode("""
        [{"id":"a","mediaType":"movie"},{"id":"b","mediaType":"movie"},{"id":"c","mediaType":"movie"}]
        """)
        XCTAssertEqual(HiddenItemsModel.neighbour(of: items[0], in: items)?.id, "b")
        XCTAssertEqual(HiddenItemsModel.neighbour(of: items[2], in: items)?.id, "b")
        XCTAssertNil(HiddenItemsModel.neighbour(of: items[0], in: [items[0]]))
    }
}
