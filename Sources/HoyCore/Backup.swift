import Foundation

// ADR 0035: バックアップ・リストア。MVP は state.db と repo/ をディレクトリコピー。

public enum BackupError: Error, CustomStringConvertible {
    case copyFailed(String)
    case sourceMissing(String)

    public var description: String {
        switch self {
        case .copyFailed(let m): return "backup copy failed: \(m)"
        case .sourceMissing(let p): return "source missing: \(p)"
        }
    }
}

public final class Backup {
    private let workspace: Workspace

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    /// `<destination>/<timestamp>/` 配下に state.db と repo をコピー。
    public func snapshot(to destination: String, now: Date = Date()) throws -> String {
        let stamp = ISO8601DateFormatter().string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let dir = (destination as NSString).appendingPathComponent(stamp)
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // WAL を本体に取り込んでからコピーする (-wal/-shm がない状態で復元できる)
        try? workspace.storage.db.run("PRAGMA wal_checkpoint(TRUNCATE)")

        let dbSrc = workspace.storage.path
        let dbDst = (dir as NSString).appendingPathComponent("state.db")
        guard fm.fileExists(atPath: dbSrc) else {
            throw BackupError.sourceMissing(dbSrc)
        }
        try fm.copyItem(atPath: dbSrc, toPath: dbDst)

        let repoSrc = (workspace.root as NSString).appendingPathComponent("repo")
        let repoDst = (dir as NSString).appendingPathComponent("repo")
        if fm.fileExists(atPath: repoSrc) {
            try fm.copyItem(atPath: repoSrc, toPath: repoDst)
        }

        return dir
    }

    /// snapshot ディレクトリから root を復元。既存の state.db / repo は上書き。
    /// daemon 起動中の呼び出しは未保証 — 停止後に行うこと。
    public static func restore(from snapshotDir: String, into root: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)

        let dbSrc = (snapshotDir as NSString).appendingPathComponent("state.db")
        let dbDst = (root as NSString).appendingPathComponent("state.db")
        guard fm.fileExists(atPath: dbSrc) else {
            throw BackupError.sourceMissing(dbSrc)
        }
        if fm.fileExists(atPath: dbDst) {
            try fm.removeItem(atPath: dbDst)
        }
        try fm.copyItem(atPath: dbSrc, toPath: dbDst)

        let repoSrc = (snapshotDir as NSString).appendingPathComponent("repo")
        let repoDst = (root as NSString).appendingPathComponent("repo")
        if fm.fileExists(atPath: repoSrc) {
            if fm.fileExists(atPath: repoDst) {
                try fm.removeItem(atPath: repoDst)
            }
            try fm.copyItem(atPath: repoSrc, toPath: repoDst)
        }
    }
}
