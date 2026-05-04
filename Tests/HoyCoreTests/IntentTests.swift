import XCTest
@testable import HoyCore

final class IntentTests: XCTestCase {
    // ADR 0008: Intent は安定IDで識別される
    func test_create_assignsNonEmptyId() {
        let intent = Intent.create(title: "first intent")
        XCTAssertFalse(intent.id.isEmpty)
    }

    func test_create_assignsUniqueIdPerCall() {
        let a = Intent.create(title: "a")
        let b = Intent.create(title: "b")
        XCTAssertNotEqual(a.id, b.id)
    }
}
