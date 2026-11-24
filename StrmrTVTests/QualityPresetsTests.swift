import XCTest
@testable import StrmrTV

/// `GET /api/quality-presets` decoding, and what the details page's Quality action shows.
final class QualityPresetsTests: XCTestCase {
    private let json = """
    {"allowRequestOverride": false, "presets": [],
     "offered": [
       {"id": "uhd", "name": "UHD", "app": "radarr", "mediaType": "movie"},
       {"id": "simple", "name": "Simple ranking", "app": "", "mediaType": ""},
       {"id": "dehd", "name": "German HD", "app": "sonarr", "mediaType": "series", "audience": "non-anime"}
     ],
     "movie": {"presetId": "uhd", "name": "UHD", "source": "title"},
     "series": {"presetId": "", "name": "", "source": ""},
     "movieDefault": {"presetId": "simple", "name": "Simple ranking", "source": "server"},
     "seriesDefault": {"presetId": "", "name": "", "source": ""}}
    """

    private func decode(_ text: String) throws -> QualityPresetChoices {
        try JSONDecoder().decode(QualityPresetChoices.self, from: Data(text.utf8))
    }

    func testDecodesAndFiltersByMediaType() throws {
        let c = try decode(json)
        XCTAssertEqual(c.offered(isMovie: true).map(\.id), ["uhd", "simple"])
        XCTAssertEqual(c.offered(isMovie: false).map(\.id), ["simple", "dehd"])
        XCTAssertEqual(c.movie.source, "title")
        XCTAssertEqual(c.defaultSelection(isMovie: true).id, "simple")
        XCTAssertEqual(c.series.id, QualityPresetChoices.simple)  // empty presetId = simple ranking
    }

    func testLabelFollowsCurrentThenPick() throws {
        let c = try decode(json)
        XCTAssertEqual(c.label(isMovie: true, picked: nil), "Quality: UHD")
        XCTAssertEqual(c.label(isMovie: true, picked: "simple"), "Quality: Simple ranking")
        XCTAssertEqual(c.label(isMovie: false, picked: "dehd"), "Quality: German HD")
        XCTAssertEqual(c.activeID(isMovie: true, picked: nil), "uhd")
    }

    func testMissingDefaultsFallBackToCurrent() throws {
        let c = try decode(#"{"offered": [{"id": "a", "name": "A", "mediaType": "movie"}], "movie": {"presetId": "a", "name": "A"}}"#)
        XCTAssertEqual(c.defaultSelection(isMovie: true).id, "a")
        XCTAssertTrue(c.offered(isMovie: false).isEmpty)  // the series page hides Quality
    }

    func testSourceResultPresetTags() throws {
        let other = try XCTUnwrap(SourceResult(["title": "X", "filterStatus": "filtered",
                                                "filterReason": "quality preset: not wanted",
                                                "attributes": ["arrQuality": "WEB-2160p", "customFormatScore": "-50",
                                                               "qualityPreset": "UHD"]], index: 3))
        XCTAssertTrue(other.isOtherQuality)
        XCTAssertTrue(other.isFiltered)
        XCTAssertEqual(other.arrQuality, "WEB-2160p")
        XCTAssertEqual(other.customFormatScore, -50)
        let identity = try XCTUnwrap(SourceResult(["title": "Y", "filterStatus": "filtered",
                                                   "filterReason": "title mismatch"], index: 4))
        XCTAssertFalse(identity.isOtherQuality)
        let ranked = try XCTUnwrap(SourceResult(["title": "Z", "filterStatus": "passed",
                                                 "attributes": ["qualityPreset": "UHD"]], index: 0))
        XCTAssertEqual(SourceSearch.rankedBy([other, ranked]), "UHD")
        XCTAssertNil(SourceSearch.rankedBy([other]))
    }
}
