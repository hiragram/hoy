import Foundation

public struct RPCRequest<Params: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let method: String
    public let params: Params
    public let auth: AuthInfo?

    public init(id: String, method: String, params: Params, auth: AuthInfo? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
        self.auth = auth
    }
}

public struct AuthInfo: Codable, Sendable, Equatable {
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

public struct RPCResponse<Result: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: String
    public let result: Result?
    public let error: RPCError?

    public init(id: String, result: Result) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    public init(id: String, error: RPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

public struct RPCError: Codable, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let data: String?

    public init(code: Int, message: String, data: String? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public enum RPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    // hoy 固有: -32000 番台
    public static let notFound = -32000
    public static let conflict = -32001
    public static let unauthorized = -32002
    public static let invalidState = -32003
}
