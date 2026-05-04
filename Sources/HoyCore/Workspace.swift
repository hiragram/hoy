import Foundation

// hoy のローカル状態ディレクトリ全体を表す。
// `~/.hoy/<workspace>/` 配下に state.db と repo/ を配置する。
public final class Workspace {
    public let root: String
    public let storage: SQLiteStorage
    public let git: Git
    public let intents: IntentRepository
    public let tasks: TaskRepository
    public let claims: ClaimRepository
    public let principals: PrincipalRepository
    public let sessions: SessionRepository
    public let audit: AuditLogRepository
    public let hooks: HookRunner

    private init(
        root: String,
        storage: SQLiteStorage,
        git: Git
    ) {
        self.root = root
        self.storage = storage
        self.git = git
        self.intents = IntentRepository(storage: storage)
        self.tasks = TaskRepository(storage: storage)
        self.claims = ClaimRepository(storage: storage)
        self.principals = PrincipalRepository(storage: storage)
        self.sessions = SessionRepository(storage: storage)
        self.audit = AuditLogRepository(storage: storage)
        self.hooks = HookRunner(workspaceRoot: root)
    }

    public static func open(at root: String) throws -> Workspace {
        let fm = FileManager.default
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)

        let dbPath = (root as NSString).appendingPathComponent("state.db")
        let storage = try SQLiteStorage.open(at: dbPath)
        try storage.migrate()

        let repoPath = (root as NSString).appendingPathComponent("repo")
        try fm.createDirectory(atPath: repoPath, withIntermediateDirectories: true)
        let git = Git(workdir: repoPath)
        try git.initIfNeeded()

        return Workspace(root: root, storage: storage, git: git)
    }
}
