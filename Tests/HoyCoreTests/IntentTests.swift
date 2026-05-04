import Testing
@testable import HoyCore

struct IntentTests {
    // ADR 0008: Intent は安定IDで識別される
    @Test func create_assignsNonEmptyId() {
        let intent = Intent.create(title: "first intent")
        #expect(!intent.id.isEmpty)
    }

    @Test func create_assignsUniqueIdPerCall() {
        let a = Intent.create(title: "a")
        let b = Intent.create(title: "b")
        #expect(a.id != b.id)
    }

    // ADR 0008: 新規作成時の version は 1
    @Test func create_initialVersionIsOne() {
        let intent = Intent.create(title: "x")
        #expect(intent.version == 1)
    }
}
