import Foundation

public struct Intent {
    public let id: String
    public let version: Int
    public let title: String
    public let body: String

    public static func create(title: String, body: String = "") -> Intent {
        return Intent(
            id: UUID().uuidString,
            version: 1,
            title: title,
            body: body
        )
    }
}
