public struct PrincipalRef: Equatable, Hashable {
    public enum Kind: String, Equatable, Hashable {
        case human
        case agent
    }

    public let id: String
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}
