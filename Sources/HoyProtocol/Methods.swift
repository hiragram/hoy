import Foundation

public protocol RPCMethod {
    associatedtype Params: Codable & Sendable
    associatedtype Result: Codable & Sendable
    static var name: String { get }
}

public enum Methods {
    // MARK: - intent

    public enum IntentCreate: RPCMethod {
        public static let name = "intent.create"
        public struct Params: Codable, Sendable, Equatable {
            public let title: String
            public let body: String?
            public let parentId: String?
            public init(title: String, body: String? = nil, parentId: String? = nil) {
                self.title = title; self.body = body; self.parentId = parentId
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let intent: IntentDTO
            public init(intent: IntentDTO) { self.intent = intent }
        }
    }

    public enum IntentGet: RPCMethod {
        public static let name = "intent.get"
        public struct Params: Codable, Sendable, Equatable {
            public let id: String
            public init(id: String) { self.id = id }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let intent: IntentDTO?
            public init(intent: IntentDTO?) { self.intent = intent }
        }
    }

    public enum IntentList: RPCMethod {
        public static let name = "intent.list"
        public struct Params: Codable, Sendable, Equatable {
            public let parentId: String?
            public let includeClosed: Bool
            public init(parentId: String? = nil, includeClosed: Bool = false) {
                self.parentId = parentId; self.includeClosed = includeClosed
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let intents: [IntentDTO]
            public init(intents: [IntentDTO]) { self.intents = intents }
        }
    }

    public enum IntentUpdate: RPCMethod {
        public static let name = "intent.update"
        public struct Params: Codable, Sendable, Equatable {
            public let id: String
            public let title: String?
            public let body: String?
            public init(id: String, title: String? = nil, body: String? = nil) {
                self.id = id; self.title = title; self.body = body
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let intent: IntentDTO
            public init(intent: IntentDTO) { self.intent = intent }
        }
    }

    public enum IntentClose: RPCMethod {
        public static let name = "intent.close"
        public struct Params: Codable, Sendable, Equatable {
            public let id: String
            public let reason: String
            public init(id: String, reason: String) { self.id = id; self.reason = reason }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let intent: IntentDTO
            public init(intent: IntentDTO) { self.intent = intent }
        }
    }

    // MARK: - task

    public enum TaskCreate: RPCMethod {
        public static let name = "task.create"
        public struct Params: Codable, Sendable, Equatable {
            public let intentId: String
            public let title: String
            public let dependsOn: [IntentRefDTO]
            public init(intentId: String, title: String, dependsOn: [IntentRefDTO] = []) {
                self.intentId = intentId; self.title = title; self.dependsOn = dependsOn
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let task: TaskDTO
            public init(task: TaskDTO) { self.task = task }
        }
    }

    public enum TaskGet: RPCMethod {
        public static let name = "task.get"
        public struct Params: Codable, Sendable, Equatable {
            public let id: String
            public init(id: String) { self.id = id }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let task: TaskDTO?
            public init(task: TaskDTO?) { self.task = task }
        }
    }

    public enum TaskList: RPCMethod {
        public static let name = "task.list"
        public struct Params: Codable, Sendable, Equatable {
            public let intentId: String?
            public init(intentId: String? = nil) { self.intentId = intentId }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let tasks: [TaskDTO]
            public init(tasks: [TaskDTO]) { self.tasks = tasks }
        }
    }

    public enum TaskComplete: RPCMethod {
        public static let name = "task.complete"
        public struct Params: Codable, Sendable, Equatable {
            public let id: String
            public init(id: String) { self.id = id }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let task: TaskDTO
            public let sha: String
            public init(task: TaskDTO, sha: String) { self.task = task; self.sha = sha }
        }
    }

    public enum TaskRevert: RPCMethod {
        public static let name = "task.revert"
        public struct Params: Codable, Sendable, Equatable {
            public let id: String
            public init(id: String) { self.id = id }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let task: TaskDTO
            public let revertSha: String
            public init(task: TaskDTO, revertSha: String) {
                self.task = task; self.revertSha = revertSha
            }
        }
    }

    // MARK: - verification

    public enum VerificationAdd: RPCMethod {
        public static let name = "verification.add"
        public struct Params: Codable, Sendable, Equatable {
            public let taskId: String
            public let kind: String
            public let category: String
            public let spec: String
            public let required: Bool
            public init(taskId: String, kind: String, category: String, spec: String, required: Bool = true) {
                self.taskId = taskId; self.kind = kind; self.category = category
                self.spec = spec; self.required = required
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let task: TaskDTO
            public init(task: TaskDTO) { self.task = task }
        }
    }

    public enum VerificationRun: RPCMethod {
        public static let name = "verification.run"
        public struct Params: Codable, Sendable, Equatable {
            public let taskId: String
            public init(taskId: String) { self.taskId = taskId }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let task: TaskDTO
            public init(task: TaskDTO) { self.task = task }
        }
    }

    public enum VerificationReport: RPCMethod {
        public static let name = "verification.report"
        public struct Params: Codable, Sendable, Equatable {
            public let taskId: String
            public let checkId: String
            public let passed: Bool
            public let evidence: String
            public init(taskId: String, checkId: String, passed: Bool, evidence: String) {
                self.taskId = taskId; self.checkId = checkId
                self.passed = passed; self.evidence = evidence
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let task: TaskDTO
            public init(task: TaskDTO) { self.task = task }
        }
    }

    public enum VerificationWaive: RPCMethod {
        public static let name = "verification.waive"
        public struct Params: Codable, Sendable, Equatable {
            public let taskId: String
            public let checkId: String
            public let reason: String
            public init(taskId: String, checkId: String, reason: String) {
                self.taskId = taskId; self.checkId = checkId; self.reason = reason
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let task: TaskDTO
            public init(task: TaskDTO) { self.task = task }
        }
    }

    // MARK: - claim

    public enum ClaimAcquire: RPCMethod {
        public static let name = "claim.acquire"
        public struct Params: Codable, Sendable, Equatable {
            public let targetIntentId: String
            public let ttlSeconds: Double
            public init(targetIntentId: String, ttlSeconds: Double = 300) {
                self.targetIntentId = targetIntentId
                self.ttlSeconds = ttlSeconds
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let claim: ClaimDTO
            public init(claim: ClaimDTO) { self.claim = claim }
        }
    }

    public enum ClaimRelease: RPCMethod {
        public static let name = "claim.release"
        public struct Params: Codable, Sendable, Equatable {
            public let targetIntentId: String
            public init(targetIntentId: String) { self.targetIntentId = targetIntentId }
        }
        public struct Result: Codable, Sendable, Equatable {
            public init() {}
        }
    }

    public enum ClaimHeartbeat: RPCMethod {
        public static let name = "claim.heartbeat"
        public struct Params: Codable, Sendable, Equatable {
            public let targetIntentId: String
            public let ttlSeconds: Double
            public init(targetIntentId: String, ttlSeconds: Double = 300) {
                self.targetIntentId = targetIntentId
                self.ttlSeconds = ttlSeconds
            }
        }
        public struct Result: Codable, Sendable, Equatable {
            public let claim: ClaimDTO
            public init(claim: ClaimDTO) { self.claim = claim }
        }
    }
}
