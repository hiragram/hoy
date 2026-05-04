// ADR 0018: Task が Intent の特定 version に依存することを表す参照
public struct IntentRef: Equatable, Hashable {
    public let id: String
    public let version: Int

    public init(id: String, version: Int) {
        self.id = id
        self.version = version
    }
}
