import Foundation

public struct Intent {
    public let id: String
    public let version: Int

    public static func create(title: String) -> Intent {
        return Intent(id: UUID().uuidString, version: 1)
    }
}
