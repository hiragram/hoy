import Foundation

public struct Intent {
    public let id: String

    public static func create(title: String) -> Intent {
        return Intent(id: UUID().uuidString)
    }
}
