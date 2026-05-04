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

    @Test func create_retainsTitle() {
        let intent = Intent.create(title: "ship MVP")
        #expect(intent.title == "ship MVP")
    }

    @Test func create_bodyDefaultsToEmpty() {
        let intent = Intent.create(title: "x")
        #expect(intent.body == "")
    }

    @Test func create_retainsBodyWhenProvided() {
        let intent = Intent.create(title: "x", body: "rationale")
        #expect(intent.body == "rationale")
    }

    // ADR 0019: 新規作成時 status は active
    @Test func create_initialStatusIsActive() {
        let intent = Intent.create(title: "x")
        #expect(intent.status == .active)
    }

    // ADR 0004: Intent は入れ子可
    @Test func create_parentIdNilByDefault() {
        let intent = Intent.create(title: "x")
        #expect(intent.parentId == nil)
    }

    @Test func create_canHaveParent() {
        let parent = Intent.create(title: "parent")
        let child = Intent.create(title: "child", parentId: parent.id)
        #expect(child.parentId == parent.id)
    }

    // ADR 0008: update で version は増分、id は不変
    @Test func update_incrementsVersionPreservesId() {
        let intent = Intent.create(title: "v1")
        let updated = intent.update(title: "v2")
        #expect(updated.id == intent.id)
        #expect(updated.version == intent.version + 1)
    }

    @Test func update_changesTitleAndBody() {
        let intent = Intent.create(title: "old", body: "old body")
        let updated = intent.update(title: "new", body: "new body")
        #expect(updated.title == "new")
        #expect(updated.body == "new body")
    }

    @Test func update_preservesParentId() {
        let intent = Intent.create(title: "x", parentId: "parent-1")
        let updated = intent.update(title: "y")
        #expect(updated.parentId == "parent-1")
    }
}
