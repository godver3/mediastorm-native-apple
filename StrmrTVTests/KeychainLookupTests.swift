import XCTest
@testable import StrmrTV

/// `Keychain.lookup` keeps "nothing saved" apart from "couldn't read": startup only forgets a
/// remote access pairing on the first.
final class KeychainLookupTests: XCTestCase {
    private let account = "KeychainLookupTests"

    override func setUp() { Keychain.delete(account) }
    override func tearDown() { Keychain.delete(account) }

    func testMissingItemIsNotFound() {
        guard case .notFound = Keychain.lookup(account) else {
            return XCTFail("expected .notFound, got \(Keychain.lookup(account))")
        }
        XCTAssertNil(Keychain.read(account))
    }

    func testSavedItemIsFound() {
        let data = Data("pairing".utf8)
        XCTAssertTrue(Keychain.write(data, account: account))
        guard case let .found(read) = Keychain.lookup(account) else {
            return XCTFail("expected .found, got \(Keychain.lookup(account))")
        }
        XCTAssertEqual(read, data)
        XCTAssertEqual(Keychain.read(account), data)
    }

    func testDeletedItemIsNotFoundAgain() {
        XCTAssertTrue(Keychain.write(Data("x".utf8), account: account))
        Keychain.delete(account)
        guard case .notFound = Keychain.lookup(account) else {
            return XCTFail("expected .notFound after delete")
        }
    }
}
