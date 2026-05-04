import Foundation

/// `<root>/policy.json` の内容。任意。無ければ空 policy を返す。
///
/// 例:
/// ```json
/// {
///   "default_verifications": [
///     { "kind": "automated", "category": "test", "spec": "swift test", "required": true }
///   ]
/// }
/// ```
public struct WorkspacePolicy: Codable, Sendable, Equatable {
    public struct DefaultVerification: Codable, Sendable, Equatable {
        public let kind: String         // "automated" | "human"
        public let category: String
        public let spec: String
        public let required: Bool
        /// ADR 0048 Stage 2: pass の前に fail を観察した履歴を要求する
        public let testFirst: Bool

        public init(
            kind: String, category: String, spec: String,
            required: Bool, testFirst: Bool = false
        ) {
            self.kind = kind; self.category = category; self.spec = spec
            self.required = required; self.testFirst = testFirst
        }
    }

    public let defaultVerifications: [DefaultVerification]

    public init(defaultVerifications: [DefaultVerification] = []) {
        self.defaultVerifications = defaultVerifications
    }

    public static let empty = WorkspacePolicy(defaultVerifications: [])

    public static func load(rootPath: String) -> WorkspacePolicy {
        let path = (rootPath as NSString).appendingPathComponent("policy.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .empty
        }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return (try? dec.decode(WorkspacePolicy.self, from: data)) ?? .empty
    }

    public func save(rootPath: String) throws {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(self)
        let path = (rootPath as NSString).appendingPathComponent("policy.json")
        try data.write(to: URL(fileURLWithPath: path))
    }
}
