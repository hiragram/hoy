public struct Intent {
    public let id: String

    public static func create(title: String) -> Intent {
        return Intent(id: "intent-1")
    }
}
